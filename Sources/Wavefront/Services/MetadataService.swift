import Foundation

/// Service for enriching track metadata using TheAudioDB API
public actor MetadataService {
    private let baseURL = "https://theaudiodb.com/api/v1/json"
    private let apiKey: String
    private let session: URLSession
    private var cache: [String: TrackMetadata] = [:]
    
    /// Initialize with API key (use "2" for free tier testing)
    public init(apiKey: String = "2", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }
    
    /// Search for track metadata by artist and track name
    public func searchTrack(artist: String, track: String) async throws -> TrackMetadata? {
        let cacheKey = "\(artist.lowercased()):\(track.lowercased())"
        
        if let cached = cache[cacheKey] {
            return cached
        }
        
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTrack = track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        let urlString = "\(baseURL)/\(apiKey)/searchtrack.php?s=\(encodedArtist)&t=\(encodedTrack)"
        
        guard let url = URL(string: urlString) else {
            throw MetadataError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MetadataError.requestFailed
        }
        
        let result = try JSONDecoder().decode(AudioDBSearchResponse.self, from: data)
        
        guard let firstTrack = result.track?.first else {
            return nil
        }
        
        let metadata = TrackMetadata(from: firstTrack)
        cache[cacheKey] = metadata
        
        return metadata
    }
    
    /// Search for album info
    public func searchAlbum(artist: String, album: String) async throws -> AlbumMetadata? {
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        
        let urlString = "\(baseURL)/\(apiKey)/searchalbum.php?s=\(encodedArtist)&a=\(encodedAlbum)"
        
        guard let url = URL(string: urlString) else {
            throw MetadataError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MetadataError.requestFailed
        }
        
        let result = try JSONDecoder().decode(AudioDBAlbumResponse.self, from: data)
        
        guard let firstAlbum = result.album?.first else {
            return nil
        }
        
        return AlbumMetadata(from: firstAlbum)
    }
    
    /// Enrich an AudioTrack with metadata from TheAudioDB
    public func enrichTrack(_ track: AudioTrack) async -> AudioTrack {
        // Try to find metadata using title as track name
        // Attempt to parse artist from filename if not present
        let artist = track.artist ?? parseArtistFromTitle(track.title)
        let trackName = parseTrackNameFromTitle(track.title)
        
        guard let artist = artist else {
            return track
        }
        
        do {
            if let metadata = try await searchTrack(artist: artist, track: trackName) {
                return AudioTrack(
                    id: track.id,
                    title: metadata.trackName ?? track.title,
                    artist: metadata.artist ?? track.artist,
                    album: metadata.album ?? track.album,
                    duration: metadata.duration ?? track.duration,
                    fileURL: track.fileURL,
                    sourceType: track.sourceType,
                    fileSize: track.fileSize,
                    dateAdded: track.dateAdded
                )
            }
        } catch {
            // Silently fail - return original track
        }
        
        return track
    }
    
    /// Batch enrich multiple tracks
    public func enrichTracks(_ tracks: [AudioTrack], maxConcurrent: Int = 5) async -> [AudioTrack] {
        var enrichedTracks: [AudioTrack] = []
        
        for track in tracks {
            // Only enrich tracks missing metadata
            if track.artist == nil || track.album == nil {
                let enriched = await enrichTrack(track)
                enrichedTracks.append(enriched)
            } else {
                enrichedTracks.append(track)
            }
        }
        
        return enrichedTracks
    }
    
    /// Clear the metadata cache
    public func clearCache() {
        cache.removeAll()
    }
    
    // MARK: - Private Helpers
    
    private func parseArtistFromTitle(_ title: String) -> String? {
        // Common patterns: "Artist - Track" or "Artist_-_Track"
        let separators = [" - ", " – ", " — ", "_-_", " _ "]
        
        for separator in separators {
            let parts = title.components(separatedBy: separator)
            if parts.count >= 2 {
                return parts[0].trimmingCharacters(in: .whitespaces)
            }
        }
        
        return nil
    }
    
    private func parseTrackNameFromTitle(_ title: String) -> String {
        let separators = [" - ", " – ", " — ", "_-_", " _ "]
        
        for separator in separators {
            let parts = title.components(separatedBy: separator)
            if parts.count >= 2 {
                return parts.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespaces)
            }
        }
        
        return title
    }
}

// MARK: - Metadata Models

public struct TrackMetadata: Codable, Sendable {
    public let trackName: String?
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let genre: String?
    public let trackNumber: Int?
    public let year: String?
    public let thumbnailURL: URL?
    public let description: String?
    
    init(from track: AudioDBTrack) {
        self.trackName = track.strTrack
        self.artist = track.strArtist
        self.album = track.strAlbum
        self.duration = track.intDuration.flatMap { Double($0) }.map { $0 / 1000.0 }
        self.genre = track.strGenre
        self.trackNumber = track.intTrackNumber.flatMap { Int($0) }
        self.year = track.intYearReleased
        self.thumbnailURL = track.strTrackThumb.flatMap { URL(string: $0) }
        self.description = track.strDescriptionEN
    }
}

public struct AlbumMetadata: Codable, Sendable {
    public let albumName: String?
    public let artist: String?
    public let year: String?
    public let genre: String?
    public let coverURL: URL?
    public let description: String?
    
    init(from album: AudioDBAlbum) {
        self.albumName = album.strAlbum
        self.artist = album.strArtist
        self.year = album.intYearReleased
        self.genre = album.strGenre
        self.coverURL = album.strAlbumThumb.flatMap { URL(string: $0) }
        self.description = album.strDescriptionEN
    }
}

// MARK: - API Response Models

struct AudioDBSearchResponse: Codable {
    let track: [AudioDBTrack]?
}

struct AudioDBTrack: Codable {
    let strTrack: String?
    let strArtist: String?
    let strAlbum: String?
    let intDuration: String?
    let strGenre: String?
    let intTrackNumber: String?
    let intYearReleased: String?
    let strTrackThumb: String?
    let strDescriptionEN: String?
}

struct AudioDBAlbumResponse: Codable {
    let album: [AudioDBAlbum]?
}

struct AudioDBAlbum: Codable {
    let strAlbum: String?
    let strArtist: String?
    let intYearReleased: String?
    let strGenre: String?
    let strAlbumThumb: String?
    let strDescriptionEN: String?
}

// MARK: - Errors

public enum MetadataError: Error, LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed
    case notFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .requestFailed: return "Metadata request failed"
        case .decodingFailed: return "Failed to decode metadata"
        case .notFound: return "Metadata not found"
        }
    }
}
