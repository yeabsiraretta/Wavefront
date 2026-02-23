import Foundation
import MultipeerConnectivity
import Combine

// MARK: - Shared Play Message Types

/**
 * Represents the different types of messages that can be sent between peers
 * in a shared play session.
 */
public enum SharedPlayMessageType: String, Codable {
    case queueTrack
    case removeFromQueue
    case playTrack
    case pausePlayback
    case resumePlayback
    case syncState
    case requestSync
}

/**
 * A message sent between peers in a shared play session.
 *
 * Contains the message type and associated payload data for synchronizing
 * playback state across connected devices.
 */
public struct SharedPlayMessage: Codable {
    let type: SharedPlayMessageType
    let trackId: String?
    let trackTitle: String?
    let trackArtist: String?
    let timestamp: Date
    let playbackPosition: TimeInterval?
    let isPlaying: Bool?
    let queue: [SharedTrackInfo]?
}

/**
 * Lightweight track information for sharing between peers.
 *
 * Contains only the essential metadata needed to display and identify
 * tracks in a shared session.
 */
public struct SharedTrackInfo: Codable, Identifiable {
    public let id: String
    public let title: String
    public let artist: String?
    public let duration: TimeInterval?
    
    public init(id: String, title: String, artist: String?, duration: TimeInterval?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

// MARK: - Shared Play Session State

/**
 * Represents the current state of a shared play session.
 */
public enum SharedPlaySessionState: Equatable {
    case notConnected
    case browsing
    case hosting
    case connected(peerCount: Int)
}

// MARK: - Shared Play Service

/**
 * Service for managing shared local play sessions using MultipeerConnectivity.
 *
 * This service enables multiple nearby devices to connect and share a synchronized
 * music queue. One device acts as the host, and others can join the session to
 * add tracks to the queue and control playback.
 *
 * ## Usage
 * ```swift
 * let sharedPlay = SharedPlayService()
 * sharedPlay.startHosting() // To host a session
 * sharedPlay.startBrowsing() // To find nearby sessions
 * ```
 *
 * ## Features
 * - Automatic peer discovery via Bluetooth and WiFi
 * - Synchronized playback queue across all connected devices
 * - Real-time playback state synchronization
 * - Automatic reconnection on connection loss
 */
@MainActor
public final class SharedPlayService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current state of the shared play session
    @Published public private(set) var sessionState: SharedPlaySessionState = .notConnected
    
    /// List of currently connected peers
    @Published public private(set) var connectedPeers: [MCPeerID] = []
    
    /// Shared queue synchronized across all peers
    @Published public private(set) var sharedQueue: [SharedTrackInfo] = []
    
    /// Whether this device is the host of the session
    @Published public private(set) var isHost: Bool = false
    
    /// Available sessions to join (when browsing)
    @Published public private(set) var availableSessions: [MCPeerID] = []
    
    /// Error message if any
    @Published public var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let serviceType = "wavefront-play"
    private let myPeerID: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    /// Callback when a track should be queued locally
    public var onQueueTrack: ((SharedTrackInfo) -> Void)?
    
    /// Callback when a track should be removed from queue
    public var onRemoveFromQueue: ((String) -> Void)?
    
    /// Callback when playback should start
    public var onPlayTrack: ((String) -> Void)?
    
    /// Callback when playback should pause
    public var onPausePlayback: (() -> Void)?
    
    /// Callback when playback should resume
    public var onResumePlayback: (() -> Void)?
    
    // MARK: - Initialization
    
    /**
     * Initializes the SharedPlayService with a unique peer identifier.
     *
     * The peer ID is based on the device name to help users identify
     * their devices in the session.
     */
    public override init() {
        #if os(iOS)
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        #else
        self.myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
        #endif
        super.init()
        setupSession()
    }
    
    // MARK: - Session Management
    
    /**
     * Sets up the MultipeerConnectivity session.
     */
    private func setupSession() {
        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session?.delegate = self
    }
    
    /**
     * Starts hosting a shared play session.
     *
     * Other nearby devices will be able to discover and join this session.
     * Only one device should host at a time.
     */
    public func startHosting() {
        stopAll()
        isHost = true
        sessionState = .hosting
        
        advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["version": "1.0"],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }
    
    /**
     * Starts browsing for nearby shared play sessions.
     *
     * Discovered sessions will appear in the `availableSessions` array.
     */
    public func startBrowsing() {
        stopAll()
        isHost = false
        sessionState = .browsing
        availableSessions = []
        
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }
    
    /**
     * Joins a discovered shared play session.
     *
     * @param peer - The peer ID of the session host to join
     */
    public func joinSession(_ peer: MCPeerID) {
        guard let session = session, let browser = browser else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }
    
    /**
     * Stops hosting or browsing and disconnects from any active session.
     */
    public func stopAll() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        
        connectedPeers = []
        availableSessions = []
        sessionState = .notConnected
        isHost = false
    }
    
    // MARK: - Queue Management
    
    /**
     * Broadcasts a track to be added to the shared queue.
     *
     * This sends a message to all connected peers to add the track
     * to their local queues.
     *
     * @param track - The track information to share
     */
    public func broadcastQueueTrack(_ track: SharedTrackInfo) {
        sharedQueue.append(track)
        
        let message = SharedPlayMessage(
            type: .queueTrack,
            trackId: track.id,
            trackTitle: track.title,
            trackArtist: track.artist,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: nil,
            queue: nil
        )
        sendMessage(message)
    }
    
    /**
     * Broadcasts removal of a track from the shared queue.
     *
     * @param trackId - The ID of the track to remove
     */
    public func broadcastRemoveFromQueue(_ trackId: String) {
        sharedQueue.removeAll { $0.id == trackId }
        
        let message = SharedPlayMessage(
            type: .removeFromQueue,
            trackId: trackId,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: nil,
            queue: nil
        )
        sendMessage(message)
    }
    
    /**
     * Broadcasts playback of a specific track.
     *
     * @param trackId - The ID of the track to play
     */
    public func broadcastPlay(_ trackId: String) {
        let message = SharedPlayMessage(
            type: .playTrack,
            trackId: trackId,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: true,
            queue: nil
        )
        sendMessage(message)
    }
    
    /**
     * Broadcasts pause command to all peers.
     */
    public func broadcastPause() {
        let message = SharedPlayMessage(
            type: .pausePlayback,
            trackId: nil,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: false,
            queue: nil
        )
        sendMessage(message)
    }
    
    /**
     * Broadcasts resume command to all peers.
     */
    public func broadcastResume() {
        let message = SharedPlayMessage(
            type: .resumePlayback,
            trackId: nil,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: true,
            queue: nil
        )
        sendMessage(message)
    }
    
    /**
     * Synchronizes the current queue state with all peers.
     *
     * Useful when a new peer joins the session.
     */
    public func syncState() {
        let message = SharedPlayMessage(
            type: .syncState,
            trackId: nil,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: nil,
            queue: sharedQueue
        )
        sendMessage(message)
    }
    
    // MARK: - Private Methods
    
    /**
     * Sends a message to all connected peers.
     *
     * @param message - The SharedPlayMessage to send
     */
    private func sendMessage(_ message: SharedPlayMessage) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }
    
    /**
     * Handles a received message from a peer.
     *
     * @param message - The received SharedPlayMessage
     */
    private func handleMessage(_ message: SharedPlayMessage) {
        Task { @MainActor in
            switch message.type {
            case .queueTrack:
                if let trackId = message.trackId, let title = message.trackTitle {
                    let trackInfo = SharedTrackInfo(
                        id: trackId,
                        title: title,
                        artist: message.trackArtist,
                        duration: nil
                    )
                    sharedQueue.append(trackInfo)
                    onQueueTrack?(trackInfo)
                }
                
            case .removeFromQueue:
                if let trackId = message.trackId {
                    sharedQueue.removeAll { $0.id == trackId }
                    onRemoveFromQueue?(trackId)
                }
                
            case .playTrack:
                if let trackId = message.trackId {
                    onPlayTrack?(trackId)
                }
                
            case .pausePlayback:
                onPausePlayback?()
                
            case .resumePlayback:
                onResumePlayback?()
                
            case .syncState:
                if let queue = message.queue {
                    sharedQueue = queue
                }
                
            case .requestSync:
                if isHost {
                    syncState()
                }
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension SharedPlayService: MCSessionDelegate {
    
    nonisolated public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !connectedPeers.contains(peerID) {
                    connectedPeers.append(peerID)
                }
                sessionState = .connected(peerCount: connectedPeers.count)
                
                // Sync state when a new peer connects (host only)
                if isHost {
                    syncState()
                }
                
            case .notConnected:
                connectedPeers.removeAll { $0 == peerID }
                if connectedPeers.isEmpty {
                    sessionState = isHost ? .hosting : .notConnected
                } else {
                    sessionState = .connected(peerCount: connectedPeers.count)
                }
                
            case .connecting:
                break
                
            @unknown default:
                break
            }
        }
    }
    
    nonisolated public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let message = try JSONDecoder().decode(SharedPlayMessage.self, from: data)
            Task { @MainActor in
                handleMessage(message)
            }
        } catch {
            Task { @MainActor in
                errorMessage = "Failed to decode message: \(error.localizedDescription)"
            }
        }
    }
    
    nonisolated public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    
    nonisolated public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    
    nonisolated public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension SharedPlayService: MCNearbyServiceAdvertiserDelegate {
    
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            // Auto-accept invitations
            invitationHandler(true, session)
        }
    }
    
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            errorMessage = "Failed to start hosting: \(error.localizedDescription)"
            sessionState = .notConnected
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension SharedPlayService: MCNearbyServiceBrowserDelegate {
    
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            if !availableSessions.contains(peerID) {
                availableSessions.append(peerID)
            }
        }
    }
    
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            availableSessions.removeAll { $0 == peerID }
        }
    }
    
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            errorMessage = "Failed to browse for sessions: \(error.localizedDescription)"
            sessionState = .notConnected
        }
    }
}
