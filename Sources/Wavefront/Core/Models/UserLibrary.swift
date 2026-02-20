import Foundation

/// Model for tracking liked songs and listening history
public final class UserLibrary: ObservableObject, @unchecked Sendable {
    public static let shared = UserLibrary()
    
    @Published public private(set) var likedSongIDs: Set<UUID> = []
    @Published public private(set) var listeningHistory: [ListeningHistoryEntry] = []
    
    private let userDefaults = UserDefaults.standard
    private let likedSongsKey = "wavefront.likedSongs"
    private let historyKey = "wavefront.listeningHistory"
    private let maxHistoryEntries = 500
    
    private init() {
        loadFromStorage()
    }
    
    // MARK: - Liked Songs
    
    public func isLiked(_ track: AudioTrack) -> Bool {
        likedSongIDs.contains(track.id)
    }
    
    public func toggleLike(_ track: AudioTrack) {
        if likedSongIDs.contains(track.id) {
            likedSongIDs.remove(track.id)
        } else {
            likedSongIDs.insert(track.id)
        }
        saveLikedSongs()
    }
    
    public func like(_ track: AudioTrack) {
        likedSongIDs.insert(track.id)
        saveLikedSongs()
    }
    
    public func unlike(_ track: AudioTrack) {
        likedSongIDs.remove(track.id)
        saveLikedSongs()
    }
    
    public func getLikedTracks(from allTracks: [AudioTrack]) -> [AudioTrack] {
        allTracks.filter { likedSongIDs.contains($0.id) }
    }
    
    // MARK: - Listening History
    
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
