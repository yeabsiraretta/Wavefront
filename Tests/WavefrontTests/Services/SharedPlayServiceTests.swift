import XCTest
@testable import Wavefront

final class SharedPlayServiceTests: XCTestCase {
    
    // MARK: - SharedPlayMessageType Tests
    
    func testMessageTypeRawValues() {
        XCTAssertEqual(SharedPlayMessageType.queueTrack.rawValue, "queueTrack")
        XCTAssertEqual(SharedPlayMessageType.removeFromQueue.rawValue, "removeFromQueue")
        XCTAssertEqual(SharedPlayMessageType.playTrack.rawValue, "playTrack")
        XCTAssertEqual(SharedPlayMessageType.pausePlayback.rawValue, "pausePlayback")
        XCTAssertEqual(SharedPlayMessageType.resumePlayback.rawValue, "resumePlayback")
        XCTAssertEqual(SharedPlayMessageType.syncState.rawValue, "syncState")
        XCTAssertEqual(SharedPlayMessageType.requestSync.rawValue, "requestSync")
    }
    
    func testMessageTypeCodable() throws {
        let type = SharedPlayMessageType.queueTrack
        let encoded = try JSONEncoder().encode(type)
        let decoded = try JSONDecoder().decode(SharedPlayMessageType.self, from: encoded)
        XCTAssertEqual(decoded, type)
    }
    
    // MARK: - SharedPlayMessage Tests
    
    func testSharedPlayMessageEncoding() throws {
        let message = SharedPlayMessage(
            type: .queueTrack,
            trackId: "track-123",
            trackTitle: "Test Song",
            trackArtist: "Test Artist",
            timestamp: Date(),
            playbackPosition: 45.5,
            isPlaying: true,
            queue: nil
        )
        
        let encoded = try JSONEncoder().encode(message)
        XCTAssertFalse(encoded.isEmpty)
        
        let decoded = try JSONDecoder().decode(SharedPlayMessage.self, from: encoded)
        XCTAssertEqual(decoded.type, .queueTrack)
        XCTAssertEqual(decoded.trackId, "track-123")
        XCTAssertEqual(decoded.trackTitle, "Test Song")
        XCTAssertEqual(decoded.trackArtist, "Test Artist")
        XCTAssertEqual(decoded.playbackPosition, 45.5)
        XCTAssertEqual(decoded.isPlaying, true)
    }
    
    func testSharedPlayMessageWithQueue() throws {
        let trackInfo = SharedTrackInfo(
            id: "track-1",
            title: "Song 1",
            artist: "Artist 1",
            duration: 180.0
        )
        
        let message = SharedPlayMessage(
            type: .syncState,
            trackId: nil,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: false,
            queue: [trackInfo]
        )
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(SharedPlayMessage.self, from: encoded)
        
        XCTAssertEqual(decoded.queue?.count, 1)
        XCTAssertEqual(decoded.queue?.first?.id, "track-1")
    }
    
    func testSharedPlayMessageWithNilValues() throws {
        let message = SharedPlayMessage(
            type: .requestSync,
            trackId: nil,
            trackTitle: nil,
            trackArtist: nil,
            timestamp: Date(),
            playbackPosition: nil,
            isPlaying: nil,
            queue: nil
        )
        
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(SharedPlayMessage.self, from: encoded)
        
        XCTAssertEqual(decoded.type, .requestSync)
        XCTAssertNil(decoded.trackId)
        XCTAssertNil(decoded.trackTitle)
        XCTAssertNil(decoded.playbackPosition)
        XCTAssertNil(decoded.isPlaying)
        XCTAssertNil(decoded.queue)
    }
    
    // MARK: - SharedTrackInfo Tests
    
    func testSharedTrackInfoInitialization() {
        let trackInfo = SharedTrackInfo(
            id: "track-123",
            title: "Test Song",
            artist: "Test Artist",
            duration: 240.0
        )
        
        XCTAssertEqual(trackInfo.id, "track-123")
        XCTAssertEqual(trackInfo.title, "Test Song")
        XCTAssertEqual(trackInfo.artist, "Test Artist")
        XCTAssertEqual(trackInfo.duration, 240.0)
    }
    
    func testSharedTrackInfoWithNilArtist() {
        let trackInfo = SharedTrackInfo(
            id: "track-123",
            title: "Test Song",
            artist: nil,
            duration: nil
        )
        
        XCTAssertNil(trackInfo.artist)
        XCTAssertNil(trackInfo.duration)
    }
    
    func testSharedTrackInfoCodable() throws {
        let trackInfo = SharedTrackInfo(
            id: "track-123",
            title: "Test Song",
            artist: "Test Artist",
            duration: 180.0
        )
        
        let encoded = try JSONEncoder().encode(trackInfo)
        let decoded = try JSONDecoder().decode(SharedTrackInfo.self, from: encoded)
        
        XCTAssertEqual(decoded.id, trackInfo.id)
        XCTAssertEqual(decoded.title, trackInfo.title)
        XCTAssertEqual(decoded.artist, trackInfo.artist)
        XCTAssertEqual(decoded.duration, trackInfo.duration)
    }
    
    func testSharedTrackInfoIdentifiable() {
        let trackInfo = SharedTrackInfo(
            id: "unique-id-123",
            title: "Test",
            artist: nil,
            duration: nil
        )
        
        // Identifiable protocol uses 'id' property
        XCTAssertEqual(trackInfo.id, "unique-id-123")
    }
    
    // MARK: - SharedPlaySessionState Tests
    
    func testSessionStateEquatable() {
        XCTAssertEqual(SharedPlaySessionState.notConnected, SharedPlaySessionState.notConnected)
        XCTAssertEqual(SharedPlaySessionState.browsing, SharedPlaySessionState.browsing)
        XCTAssertEqual(SharedPlaySessionState.hosting, SharedPlaySessionState.hosting)
        XCTAssertEqual(SharedPlaySessionState.connected(peerCount: 2), SharedPlaySessionState.connected(peerCount: 2))
        
        XCTAssertNotEqual(SharedPlaySessionState.notConnected, SharedPlaySessionState.browsing)
        XCTAssertNotEqual(SharedPlaySessionState.connected(peerCount: 1), SharedPlaySessionState.connected(peerCount: 2))
    }
    
    func testSessionStateConnectedWithDifferentPeerCounts() {
        let state1 = SharedPlaySessionState.connected(peerCount: 1)
        let state2 = SharedPlaySessionState.connected(peerCount: 3)
        let state3 = SharedPlaySessionState.connected(peerCount: 1)
        
        XCTAssertNotEqual(state1, state2)
        XCTAssertEqual(state1, state3)
    }
    
    // MARK: - Service Initialization Tests
    
    @MainActor
    func testSharedPlayServiceInitialization() {
        let service = SharedPlayService()
        XCTAssertNotNil(service)
        XCTAssertEqual(service.sessionState, .notConnected)
    }
    
    @MainActor
    func testSharedPlayServiceInitialState() {
        let service = SharedPlayService()
        XCTAssertEqual(service.sessionState, .notConnected)
        XCTAssertTrue(service.connectedPeers.isEmpty)
        XCTAssertTrue(service.sharedQueue.isEmpty)
    }
}

// MARK: - Message Type Coverage Tests

extension SharedPlayServiceTests {
    
    func testAllMessageTypesDecodable() throws {
        let types: [SharedPlayMessageType] = [
            .queueTrack,
            .removeFromQueue,
            .playTrack,
            .pausePlayback,
            .resumePlayback,
            .syncState,
            .requestSync
        ]
        
        for type in types {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(SharedPlayMessageType.self, from: encoded)
            XCTAssertEqual(decoded, type)
        }
    }
}
