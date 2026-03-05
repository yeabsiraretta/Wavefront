import Foundation

/// Last.fm API service for scrobbling and music recommendations
public final class LastFMService: ObservableObject {
    public static let shared = LastFMService()
    
    private let apiKey = "YOUR_LASTFM_API_KEY" // User needs to set this
    private let apiSecret = "YOUR_LASTFM_API_SECRET"
    private let baseURL = "https://ws.audioscrobbler.com/2.0/"
    
    @Published public var isAuthenticated = false
    @Published public var username: String?
    @Published public var scrobbleCount: Int = 0
    @Published public var isScrobblingEnabled = true
    
    private var sessionKey: String?
    private var scrobbleQueue: [(track: AudioTrack, timestamp: Date)] = []
    private let scrobbleThreshold: TimeInterval = 30 // Minimum seconds before scrobbling
    
    private init() {
        loadCredentials()
    }
    
    // MARK: - Authentication
    
    /// Set API credentials (user must obtain from Last.fm)
    public func setCredentials(apiKey: String, apiSecret: String) {
        UserDefaults.standard.set(apiKey, forKey: "lastfm_api_key")
        UserDefaults.standard.set(apiSecret, forKey: "lastfm_api_secret")
    }
    
    /// Authenticate with Last.fm using username and password
    public func authenticate(username: String, password: String) async throws {
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        let apiSecret = UserDefaults.standard.string(forKey: "lastfm_api_secret") ?? self.apiSecret
        
        guard apiKey != "YOUR_LASTFM_API_KEY" else {
            throw LastFMError.missingAPIKey
        }
        
        let params = [
            "api_key": apiKey,
            "method": "auth.getMobileSession",
            "password": password,
            "username": username
        ]
        
        let signature = createSignature(params: params, secret: apiSecret)
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        urlComponents.queryItems?.append(URLQueryItem(name: "api_sig", value: signature))
        urlComponents.queryItems?.append(URLQueryItem(name: "format", value: "json"))
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LastFMError.authenticationFailed
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        if let session = json?["session"] as? [String: Any],
           let key = session["key"] as? String,
           let name = session["name"] as? String {
            await MainActor.run {
                self.sessionKey = key
                self.username = name
                self.isAuthenticated = true
                self.saveCredentials()
            }
        } else if let error = json?["error"] as? Int {
            throw LastFMError.apiError(code: error, message: json?["message"] as? String ?? "Unknown error")
        }
    }
    
    /// Log out and clear credentials
    public func logout() {
        sessionKey = nil
        username = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "lastfm_session_key")
        UserDefaults.standard.removeObject(forKey: "lastfm_username")
    }
    
    // MARK: - Scrobbling
    
    /// Scrobble a track (report it as played)
    public func scrobble(track: AudioTrack, playedAt: Date = Date()) async {
        guard isScrobblingEnabled, isAuthenticated, let sessionKey = sessionKey else { return }
        
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        let apiSecret = UserDefaults.standard.string(forKey: "lastfm_api_secret") ?? self.apiSecret
        
        let timestamp = String(Int(playedAt.timeIntervalSince1970))
        
        var params: [String: String] = [
            "api_key": apiKey,
            "method": "track.scrobble",
            "sk": sessionKey,
            "timestamp": timestamp,
            "track": track.title
        ]
        
        if let artist = track.artist {
            params["artist"] = artist
        } else {
            params["artist"] = "Unknown Artist"
        }
        
        if let album = track.album {
            params["album"] = album
        }
        
        if let duration = track.duration {
            params["duration"] = String(Int(duration))
        }
        
        let signature = createSignature(params: params, secret: apiSecret)
        params["api_sig"] = signature
        params["format"] = "json"
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let scrobbles = json["scrobbles"] as? [String: Any],
               let attr = scrobbles["@attr"] as? [String: Any],
               let accepted = attr["accepted"] as? Int, accepted > 0 {
                await MainActor.run {
                    self.scrobbleCount += 1
                }
                Logger.success("Scrobbled: \(track.title)", category: .general)
            }
        } catch {
            Logger.error("Failed to scrobble", error: error, category: .general)
        }
    }
    
    /// Update "Now Playing" status
    public func updateNowPlaying(track: AudioTrack) async {
        guard isScrobblingEnabled, isAuthenticated, let sessionKey = sessionKey else { return }
        
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        let apiSecret = UserDefaults.standard.string(forKey: "lastfm_api_secret") ?? self.apiSecret
        
        var params: [String: String] = [
            "api_key": apiKey,
            "method": "track.updateNowPlaying",
            "sk": sessionKey,
            "track": track.title
        ]
        
        if let artist = track.artist {
            params["artist"] = artist
        } else {
            params["artist"] = "Unknown Artist"
        }
        
        if let album = track.album {
            params["album"] = album
        }
        
        if let duration = track.duration {
            params["duration"] = String(Int(duration))
        }
        
        let signature = createSignature(params: params, secret: apiSecret)
        params["api_sig"] = signature
        params["format"] = "json"
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        
        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        
        do {
            let _ = try await URLSession.shared.data(for: request)
            Logger.debug("Updated Now Playing: \(track.title)", category: .general)
        } catch {
            Logger.error("Failed to update Now Playing", error: error, category: .general)
        }
    }
    
    // MARK: - Track Info / Metadata
    
    /// Fetched track metadata from Last.fm
    public struct TrackMetadata {
        public let title: String
        public let artist: String
        public let album: String?
        public let duration: TimeInterval?
        public let playCount: Int?
        public let listeners: Int?
        public let tags: [String]
    }
    
    /// Get track info/metadata from Last.fm by searching with title
    public func getTrackInfo(title: String, artist: String? = nil) async throws -> TrackMetadata? {
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        
        var urlComponents = URLComponents(string: baseURL)!
        var queryItems = [
            URLQueryItem(name: "method", value: "track.search"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "track", value: title),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        if let artist = artist {
            queryItems.append(URLQueryItem(name: "artist", value: artist))
        }
        
        urlComponents.queryItems = queryItems
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Parse search results
        guard let results = json?["results"] as? [String: Any],
              let trackMatches = results["trackmatches"] as? [String: Any],
              let tracks = trackMatches["track"] as? [[String: Any]],
              let firstTrack = tracks.first else {
            return nil
        }
        
        let foundTitle = firstTrack["name"] as? String ?? title
        let foundArtist = firstTrack["artist"] as? String ?? "Unknown Artist"
        
        // Now get detailed track info
        return try await getDetailedTrackInfo(track: foundTitle, artist: foundArtist)
    }
    
    /// Get detailed track info from Last.fm
    public func getDetailedTrackInfo(track: String, artist: String) async throws -> TrackMetadata? {
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "method", value: "track.getInfo"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "track", value: track),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let trackInfo = json?["track"] as? [String: Any] else {
            return nil
        }
        
        let title = trackInfo["name"] as? String ?? track
        let artistName = (trackInfo["artist"] as? [String: Any])?["name"] as? String ?? artist
        
        // Get album info
        var album: String?
        if let albumInfo = trackInfo["album"] as? [String: Any] {
            album = albumInfo["title"] as? String
        }
        
        // Get duration
        var duration: TimeInterval?
        if let durationStr = trackInfo["duration"] as? String, let ms = Double(durationStr) {
            duration = ms / 1000.0
        } else if let durationInt = trackInfo["duration"] as? Int {
            duration = Double(durationInt) / 1000.0
        }
        
        // Get play count and listeners
        var playCount: Int?
        var listeners: Int?
        if let pc = trackInfo["playcount"] as? String { playCount = Int(pc) }
        else if let pc = trackInfo["playcount"] as? Int { playCount = pc }
        if let l = trackInfo["listeners"] as? String { listeners = Int(l) }
        else if let l = trackInfo["listeners"] as? Int { listeners = l }
        
        // Get tags
        var tags: [String] = []
        if let topTags = trackInfo["toptags"] as? [String: Any],
           let tagList = topTags["tag"] as? [[String: Any]] {
            tags = tagList.compactMap { $0["name"] as? String }
        }
        
        return TrackMetadata(
            title: title,
            artist: artistName,
            album: album,
            duration: duration,
            playCount: playCount,
            listeners: listeners,
            tags: tags
        )
    }
    
    // MARK: - Recommendations
    
    /// Get similar tracks based on a track
    public func getSimilarTracks(to track: AudioTrack, limit: Int = 10) async throws -> [RecommendedTrack] {
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        
        guard let artist = track.artist else {
            throw LastFMError.missingArtist
        }
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "method", value: "track.getSimilar"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "track", value: track.title),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let similarTracks = json?["similartracks"] as? [String: Any],
              let trackList = similarTracks["track"] as? [[String: Any]] else {
            return []
        }
        
        return trackList.compactMap { RecommendedTrack(from: $0) }
    }
    
    /// Get recommended tracks based on user's listening history
    public func getRecommendations(limit: Int = 20) async throws -> [RecommendedTrack] {
        guard isAuthenticated, let username = username else {
            throw LastFMError.notAuthenticated
        }
        
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        
        // Get user's top artists first
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "method", value: "user.getTopArtists"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "user", value: username),
            URLQueryItem(name: "limit", value: "5"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let topArtists = json?["topartists"] as? [String: Any],
              let artistList = topArtists["artist"] as? [[String: Any]] else {
            return []
        }
        
        // Get similar artists for each top artist
        var recommendations: [RecommendedTrack] = []
        
        for artist in artistList.prefix(3) {
            guard let artistName = artist["name"] as? String else { continue }
            
            let similar = try await getSimilarArtistTracks(artist: artistName, limit: limit / 3)
            recommendations.append(contentsOf: similar)
        }
        
        return Array(recommendations.shuffled().prefix(limit))
    }
    
    /// Get top tracks from an artist similar to the given artist
    private func getSimilarArtistTracks(artist: String, limit: Int) async throws -> [RecommendedTrack] {
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        
        // First get similar artists
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "method", value: "artist.getSimilar"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "limit", value: "3"),
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let similarArtists = json?["similarartists"] as? [String: Any],
              let artistList = similarArtists["artist"] as? [[String: Any]] else {
            return []
        }
        
        var tracks: [RecommendedTrack] = []
        
        for similarArtist in artistList {
            guard let artistName = similarArtist["name"] as? String else { continue }
            
            // Get top tracks for this similar artist
            let topTracks = try await getArtistTopTracks(artist: artistName, limit: limit)
            tracks.append(contentsOf: topTracks)
        }
        
        return tracks
    }
    
    /// Get top tracks for an artist
    public func getArtistTopTracks(artist: String, limit: Int = 5) async throws -> [RecommendedTrack] {
        let apiKey = UserDefaults.standard.string(forKey: "lastfm_api_key") ?? self.apiKey
        
        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "method", value: "artist.getTopTracks"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "format", value: "json")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: urlComponents.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let topTracks = json?["toptracks"] as? [String: Any],
              let trackList = topTracks["track"] as? [[String: Any]] else {
            return []
        }
        
        return trackList.compactMap { RecommendedTrack(from: $0) }
    }
    
    // MARK: - Private Methods
    
    private func createSignature(params: [String: String], secret: String) -> String {
        let sortedParams = params.sorted { $0.key < $1.key }
        var sigString = sortedParams.map { "\($0.key)\($0.value)" }.joined()
        sigString += secret
        return sigString.md5()
    }
    
    private func loadCredentials() {
        if let key = UserDefaults.standard.string(forKey: "lastfm_session_key"),
           let name = UserDefaults.standard.string(forKey: "lastfm_username") {
            sessionKey = key
            username = name
            isAuthenticated = true
        }
        
        isScrobblingEnabled = UserDefaults.standard.bool(forKey: "lastfm_scrobbling_enabled")
    }
    
    private func saveCredentials() {
        if let sessionKey = sessionKey {
            UserDefaults.standard.set(sessionKey, forKey: "lastfm_session_key")
        }
        if let username = username {
            UserDefaults.standard.set(username, forKey: "lastfm_username")
        }
    }
    
    /// Toggle scrobbling on/off
    public func setScrobblingEnabled(_ enabled: Bool) {
        isScrobblingEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "lastfm_scrobbling_enabled")
    }
}

// MARK: - Supporting Types

/// Error types for Last.fm operations
public enum LastFMError: LocalizedError {
    case missingAPIKey
    case missingArtist
    case authenticationFailed
    case notAuthenticated
    case apiError(code: Int, message: String)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Last.fm API key not configured. Please set your API key in settings."
        case .missingArtist:
            return "Track is missing artist information"
        case .authenticationFailed:
            return "Failed to authenticate with Last.fm"
        case .notAuthenticated:
            return "Please sign in to Last.fm first"
        case .apiError(let code, let message):
            return "Last.fm API error \(code): \(message)"
        }
    }
}

/// A track recommended by Last.fm
public struct RecommendedTrack: Identifiable {
    public let id = UUID()
    public let title: String
    public let artist: String
    public let matchScore: Double?
    public let playCount: Int?
    public let url: String?
    
    init?(from json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        self.title = name
        
        if let artistInfo = json["artist"] as? [String: Any],
           let artistName = artistInfo["name"] as? String {
            self.artist = artistName
        } else if let artistName = json["artist"] as? String {
            self.artist = artistName
        } else {
            return nil
        }
        
        if let match = json["match"] as? String {
            self.matchScore = Double(match)
        } else if let match = json["match"] as? Double {
            self.matchScore = match
        } else {
            self.matchScore = nil
        }
        
        if let playcount = json["playcount"] as? String {
            self.playCount = Int(playcount)
        } else if let playcount = json["playcount"] as? Int {
            self.playCount = playcount
        } else {
            self.playCount = nil
        }
        
        self.url = json["url"] as? String
    }
}

// MARK: - String MD5 Extension

import CryptoKit

extension String {
    func md5() -> String {
        guard let data = self.data(using: .utf8) else { return self }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
