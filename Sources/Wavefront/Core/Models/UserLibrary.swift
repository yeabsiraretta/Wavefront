import Foundation

/**
 * Singleton class for managing user's music library preferences.
 *
 * Handles liked songs, listening history, and other user-specific data.
 * Data is persisted to UserDefaults and loaded on app launch.
 *
 * ## Features
 * - Track liked/favorite songs
 * - Record and retrieve listening history
 * - Persist data across app sessions
 *
 * ## Usage
 * ```swift
 * UserLibrary.shared.like(track)
 * let isLiked = UserLibrary.shared.isLiked(track)
 * ```
 *
 * @property likedSongIDs - Set of UUIDs for liked tracks
 * @property listeningHistory - Array of listening history entries
 */
public final class UserLibrary: ObservableObject, @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = UserLibrary()
    
    /// Set of track IDs that the user has liked
    @Published public private(set) var likedSongIDs: Set<UUID> = []
    
    /// Array of listening history entries, most recent first
    @Published public private(set) var listeningHistory: [ListeningHistoryEntry] = []
    
    private let userDefaults = UserDefaults.standard
    private let likedSongsKey = "wavefront.likedSongs"
    private let historyKey = "wavefront.listeningHistory"
    private let maxHistoryEntries = 500
    
    /**
     * Private initializer to enforce singleton pattern.
     * Loads persisted data from UserDefaults on initialization.
     */
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Liked Songs
    
    /**
     * Checks if a track is in the user's liked songs.
     *
     * @param track - The AudioTrack to check
     * @returns true if the track is liked, false otherwise
     */
    public func isLiked(_ track: AudioTrack) -> Bool {
        likedSongIDs.contains(track.id)
    }
    
    /**
     * Toggles the liked status of a track.
     *
     * If the track is liked, it will be unliked. If unliked, it will be liked.
     * Changes are automatically persisted to storage.
     *
     * @param track - The AudioTrack to toggle
     */
    public func toggleLike(_ track: AudioTrack) {
        if likedSongIDs.contains(track.id) {
            likedSongIDs.remove(track.id)
        } else {
            likedSongIDs.insert(track.id)
        }
        saveLikedSongs()
    }
    
    /**
     * Adds a track to the user's liked songs.
     *
     * If the track is already liked, this has no effect.
     * Changes are automatically persisted to storage.
     *
     * @param track - The AudioTrack to like
     */
    public func like(_ track: AudioTrack) {
        likedSongIDs.insert(track.id)
        saveLikedSongs()
    }
    
    /**
     * Removes a track from the user's liked songs.
     *
     * If the track is not liked, this has no effect.
     * Changes are automatically persisted to storage.
     *
     * @param track - The AudioTrack to unlike
     */
    public func unlike(_ track: AudioTrack) {
        likedSongIDs.remove(track.id)
        saveLikedSongs()
    }
    
    /**
     * Filters a list of tracks to only include liked tracks.
     *
     * @param allTracks - Array of AudioTracks to filter
     * @returns Array containing only tracks that are liked
     */
    public func getLikedTracks(from allTracks: [AudioTrack]) -> [AudioTrack] {
        allTracks.filter { likedSongIDs.contains($0.id) }
    }
    
    // MARK: - Listening History
    
    /**
     * Records a track play to the listening history.
     *
     * Creates a new history entry with the current timestamp and inserts
     * it at the beginning of the history. Trims history to maxHistoryEntries
     * if necessary.
     *
     * @param track - The AudioTrack that was played
     */
    public func recordPlay(_ track: AudioTrack) {
        let entry = ListeningHistoryEntry(
            trackID: track.id,
            trackTitle: track.title,
            artist: track.artist,
            album: track.album,
            playedAt: Date()
        )
        
        listeningHistory.insert(entry, at: 0)
        
        // Trim history if needed
        if listeningHistory.count > maxHistoryEntries {
            listeningHistory = Array(listeningHistory.prefix(maxHistoryEntries))
        }
        
        saveHistory()
    }
    
    public func getRecentTracks(from allTracks: [AudioTrack], limit: Int = 50) -> [AudioTrack] {
        let recentIDs = listeningHistory.prefix(limit).map { $0.trackID }
        var result: [AudioTrack] = []
        
        for id in recentIDs {
            if let track = allTracks.first(where: { $0.id == id }),
               !result.contains(where: { $0.id == id }) {
                result.append(track)
            }
        }
        
        return result
    }
    
    public func clearHistory() {
        listeningHistory.removeAll()
        saveHistory()
    }
    
    // MARK: - Persistence
    
    private func loadFromStorage() {
        // Load liked songs
        if let data = userDefaults.data(forKey: likedSongsKey),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            likedSongIDs = Set(ids)
        }
        
        // Load history
        if let data = userDefaults.data(forKey: historyKey),
           let history = try? JSONDecoder().decode([ListeningHistoryEntry].self, from: data) {
            listeningHistory = history
        }
    }
    
    private func saveLikedSongs() {
        if let data = try? JSONEncoder().encode(Array(likedSongIDs)) {
            userDefaults.set(data, forKey: likedSongsKey)
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(listeningHistory) {
            userDefaults.set(data, forKey: historyKey)
        }
    }
}

/// Entry in listening history
public struct ListeningHistoryEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let trackID: UUID
    public let trackTitle: String
    public let artist: String?
    public let album: String?
    public let playedAt: Date
    
    public init(
        id: UUID = UUID(),
        trackID: UUID,
        trackTitle: String,
        artist: String?,
        album: String?,
        playedAt: Date
    ) {
        self.id = id
        self.trackID = trackID
        self.trackTitle = trackTitle
        self.artist = artist
        self.album = album
        self.playedAt = playedAt
    }
}

/// Album grouping helper
public struct Album: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let artist: String?
    public let tracks: [AudioTrack]
    public let artworkURL: URL?
    
    public init(name: String, artist: String?, tracks: [AudioTrack], artworkURL: URL? = nil) {
        self.id = "\(artist ?? "Unknown"):\(name)"
        self.name = name
        self.artist = artist
        self.tracks = tracks
        self.artworkURL = artworkURL
    }
    
    public static func groupTracks(_ tracks: [AudioTrack]) -> [Album] {
        let grouped = Dictionary(grouping: tracks) { track in
            track.album ?? "Unknown Album"
        }
        
        return grouped.map { (albumName, albumTracks) in
            let artist = albumTracks.first?.artist
            return Album(name: albumName, artist: artist, tracks: albumTracks.sorted { 
                ($0.title) < ($1.title)
            })
        }.sorted { $0.name < $1.name }
    }
}
