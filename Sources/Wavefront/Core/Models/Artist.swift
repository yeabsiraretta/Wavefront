import Foundation

/// Represents an artist with their associated tracks
public struct Artist: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let tracks: [AudioTrack]
    
    public init(name: String, tracks: [AudioTrack]) {
        self.id = name.lowercased()
        self.name = name
        self.tracks = tracks
    }
    
    /// Number of tracks by this artist
    public var trackCount: Int {
        tracks.count
    }
    
    /// Total duration of all tracks
    public var totalDuration: TimeInterval {
        tracks.compactMap { $0.duration }.reduce(0, +)
    }
    
    /// Unique albums by this artist
    public var albums: [String] {
        Array(Set(tracks.compactMap { $0.album })).sorted()
    }
    
    /// Groups tracks by artist name
    public static func groupTracks(_ tracks: [AudioTrack]) -> [Artist] {
        let grouped = Dictionary(grouping: tracks) { track -> String in
            track.artist ?? "Unknown Artist"
        }
        
        return grouped.map { name, tracks in
            Artist(name: name, tracks: tracks.sorted { $0.title < $1.title })
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: Artist, rhs: Artist) -> Bool {
        lhs.id == rhs.id
    }
}
