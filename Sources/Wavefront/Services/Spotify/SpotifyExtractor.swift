import Foundation

/**
 * Error types for Spotify extraction operations.
 *
 * @case invalidURL - The provided Spotify URL is malformed
 * @case extractionFailed - Web scraping or parsing failed
 * @case noYouTubeExtractor - YouTube extractor unavailable for download
 * @case networkError - Network request failed
 */
public enum SpotifyExtractionError: Error, LocalizedError {
    case invalidURL
    case extractionFailed(String)
    case noYouTubeExtractor
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Spotify URL"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        case .noYouTubeExtractor:
            return "YouTube extractor not available"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/**
 * Extracts Spotify content info via web scraping.
 *
 * This actor scrapes Spotify embed pages to extract track metadata
 * without requiring API credentials. Audio is then downloaded by
 * matching tracks on YouTube.
 *
 * ## Features
 * - Track, playlist, and album URL parsing
 * - Web scraping for metadata extraction
 * - YouTube search for audio matching
 * - No API credentials required
 *
 * ## Supported URL Formats
 * - open.spotify.com/track/ID
 * - open.spotify.com/playlist/ID
 * - open.spotify.com/album/ID
 * - spotify:track:ID (URI format)
 *
 * ## Usage
 * ```swift
 * let extractor = try SpotifyExtractor()
 * let tracks = try await extractor.scrapePlaylist(id: "playlistId")
 * let result = try await extractor.downloadTrack(track)
 * ```
 */
public actor SpotifyExtractor {
    private let youtubeExtractor: YouTubeKitExtractor?
    private let session: URLSession
    
    /// Result of a Spotify URL parse
    public enum SpotifyURLType {
        case track(id: String)
        case playlist(id: String)
        case album(id: String)
        case invalid
    }
    
    /// Scraped track info from Spotify web page
    public struct ScrapedTrack {
        public let name: String
        public let artist: String
        public let album: String
        public let duration: TimeInterval
        public let artworkURL: URL?
        
        public var searchQuery: String {
            "\(artist) - \(name)"
        }
    }
    
    /// Download result with full metadata
    public struct SpotifyDownloadResult {
        public let localURL: URL
        public let title: String
        public let artist: String
        public let album: String
        public let duration: TimeInterval
        public let albumArtURL: URL?
    }
    
    public init() throws {
        self.youtubeExtractor = try? YouTubeKitExtractor()
        self.session = URLSession.shared
    }
    
    // MARK: - URL Parsing
    
    /// Parse a Spotify URL to determine its type and ID
    public func parseURL(_ urlString: String) -> SpotifyURLType {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Handle open.spotify.com URLs
        if let url = URL(string: trimmed),
           let host = url.host,
           host.contains("spotify.com") {
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            
            if pathComponents.count >= 2 {
                let type = pathComponents[0]
                var id = pathComponents[1]
                
                // Remove query parameters from ID
                if let queryStart = id.firstIndex(of: "?") {
                    id = String(id[..<queryStart])
                }
                
                switch type {
                case "track":
                    return .track(id: id)
                case "playlist":
                    return .playlist(id: id)
                case "album":
                    return .album(id: id)
                default:
                    return .invalid
                }
            }
        }
        
        // Handle spotify: URIs
        if trimmed.hasPrefix("spotify:") {
            let components = trimmed.split(separator: ":")
            if components.count >= 3 {
                let type = String(components[1])
                let id = String(components[2])
                
                switch type {
                case "track":
                    return .track(id: id)
                case "playlist":
                    return .playlist(id: id)
                case "album":
                    return .album(id: id)
                default:
                    return .invalid
                }
            }
        }
        
        return .invalid
    }
    
    // MARK: - Web Scraping
    
    /// Scrape track metadata from Spotify embed page
    public func scrapeTrack(id: String) async throws -> ScrapedTrack {
        let embedURL = "https://open.spotify.com/embed/track/\(id)"
        let html = try await fetchPage(url: embedURL)
        return try parseTrackFromEmbed(html: html)
    }
    
    /// Scrape playlist tracks from Spotify embed page
    public func scrapePlaylist(id: String) async throws -> (name: String, tracks: [ScrapedTrack]) {
        Logger.info("Scraping playlist with ID: \(id)", category: .spotify)
        let embedURL = "https://open.spotify.com/embed/playlist/\(id)"
        Logger.debug("Fetching embed URL: \(embedURL)", category: .spotify)
        
        let html = try await fetchPage(url: embedURL)
        Logger.debug("Received HTML response: \(html.count) characters", category: .spotify)
        
        let result = try await parsePlaylistFromEmbed(html: html, id: id)
        Logger.info("Parsed playlist '\(result.name)' with \(result.tracks.count) tracks", category: .spotify)
        
        if result.tracks.isEmpty {
            Logger.warning("No tracks found in playlist - HTML preview: \(String(html.prefix(500)))", category: .spotify)
        }
        
        return result
    }
    
    /// Scrape album tracks from Spotify embed page
    public func scrapeAlbum(id: String) async throws -> (name: String, tracks: [ScrapedTrack]) {
        let embedURL = "https://open.spotify.com/embed/album/\(id)"
        let html = try await fetchPage(url: embedURL)
        return try await parseAlbumFromEmbed(html: html, id: id)
    }
    
    private func fetchPage(url urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid URL: \(urlString)", category: .spotify)
            throw SpotifyExtractionError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        Logger.logRequest(url: urlString, category: .spotify)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                Logger.error("No HTTP response received", category: .spotify)
                throw SpotifyExtractionError.extractionFailed("No HTTP response")
            }
            
            Logger.logResponse(url: urlString, statusCode: httpResponse.statusCode, category: .spotify)
            
            guard (200...299).contains(httpResponse.statusCode) else {
                Logger.error("HTTP error \(httpResponse.statusCode) for \(urlString)", category: .spotify)
                throw SpotifyExtractionError.extractionFailed("HTTP \(httpResponse.statusCode)")
            }
            
            guard let html = String(data: data, encoding: .utf8) else {
                Logger.error("Could not decode response as UTF-8", category: .spotify)
                throw SpotifyExtractionError.extractionFailed("Could not decode page")
            }
            
            return html
        } catch let error as SpotifyExtractionError {
            throw error
        } catch {
            Logger.error("Network request failed", error: error, category: .spotify)
            throw SpotifyExtractionError.networkError(error)
        }
    }
    
    private func parseTrackFromEmbed(html: String) throws -> ScrapedTrack {
        // Extract track info from og:title meta tag: "Track Name - song and lyrics by Artist"
        // Or from structured data in the page
        
        var name = "Unknown Track"
        var artist = "Unknown Artist"
        var album = "Unknown Album"
        var duration: TimeInterval = 0
        var artworkURL: URL?
        
        // Try to extract from og:title
        if let titleMatch = html.range(of: #"<meta property="og:title" content="([^"]+)""#, options: .regularExpression) {
            let titleContent = String(html[titleMatch])
            if let contentRange = titleContent.range(of: #"content="([^"]+)""#, options: .regularExpression) {
                var title = String(html[contentRange])
                title = title.replacingOccurrences(of: "content=\"", with: "")
                title = title.replacingOccurrences(of: "\"", with: "")
                
                // Parse "Track Name - song and lyrics by Artist"
                if let byRange = title.range(of: " - song and lyrics by ") {
                    name = String(title[..<byRange.lowerBound])
                    artist = String(title[byRange.upperBound...])
                } else if let byRange = title.range(of: " - song by ") {
                    name = String(title[..<byRange.lowerBound])
                    artist = String(title[byRange.upperBound...])
                } else if title.contains(" · ") {
                    let parts = title.components(separatedBy: " · ")
                    if parts.count >= 2 {
                        name = parts[0]
                        artist = parts[1]
                    }
                }
            }
        }
        
        // Try to extract artwork from og:image
        if let imageMatch = html.range(of: #"<meta property="og:image" content="([^"]+)""#, options: .regularExpression) {
            let imageContent = String(html[imageMatch])
            if let urlStart = imageContent.range(of: "content=\""),
               let urlEnd = imageContent.range(of: "\"", range: urlStart.upperBound..<imageContent.endIndex) {
                let urlString = String(imageContent[urlStart.upperBound..<urlEnd.lowerBound])
                artworkURL = URL(string: urlString)
            }
        }
        
        // Try to extract duration from structured data
        if let durationMatch = html.range(of: #""duration_ms"\s*:\s*(\d+)"#, options: .regularExpression) {
            let durationStr = String(html[durationMatch])
            if let numMatch = durationStr.range(of: #"\d+"#, options: .regularExpression) {
                if let ms = Double(durationStr[numMatch]) {
                    duration = ms / 1000.0
                }
            }
        }
        
        // Clean up HTML entities
        name = decodeHTMLEntities(name)
        artist = decodeHTMLEntities(artist)
        album = decodeHTMLEntities(album)
        
        return ScrapedTrack(
            name: name,
            artist: artist,
            album: album,
            duration: duration,
            artworkURL: artworkURL
        )
    }
    
    private func parsePlaylistFromEmbed(html: String, id: String) async throws -> (name: String, tracks: [ScrapedTrack]) {
        var playlistName = "Spotify Playlist"
        var tracks: [ScrapedTrack] = []
        
        Logger.debug("Parsing playlist embed HTML (\(html.count) chars)", category: .spotify)
        
        // Extract playlist name from og:title
        if let titleMatch = html.range(of: #"<meta property="og:title" content="([^"]+)""#, options: .regularExpression) {
            let titleContent = String(html[titleMatch])
            if let contentRange = titleContent.range(of: #"content="([^"]+)""#, options: .regularExpression) {
                var title = String(html[contentRange])
                title = title.replacingOccurrences(of: "content=\"", with: "")
                title = title.replacingOccurrences(of: "\"", with: "")
                playlistName = decodeHTMLEntities(title)
                Logger.info("Found playlist name: \(playlistName)", category: .spotify)
            }
        }
        
        // Try multiple patterns to extract tracks from JSON data
        let patterns = [
            // Pattern 1: track items array format
            #"\{"name":"([^"]+)","uri":"spotify:track:[^"]+","uid":"[^"]*","artists":\[\{"name":"([^"]+)""#,
            // Pattern 2: Standard track object with artists array
            #""name"\s*:\s*"([^"]+)"[^}]*"artists"\s*:\s*\[\s*\{\s*"name"\s*:\s*"([^"]+)""#,
            // Pattern 3: Compact format
            #"\{"name":"([^"]+)","type":"track"[^}]*"artists":\[\{"name":"([^"]+)""#,
            // Pattern 4: Track wrapper
            #""track":\{"name":"([^"]+)"[^}]*"artists":\[\{"name":"([^"]+)""#,
            // Pattern 5: Simple name/artists pair (more permissive)
            #""name":"([^"]{2,100})","[^"]*artists[^"]*":\[\{[^}]*"name":"([^"]+)""#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(html.startIndex..., in: html)
                let matches = regex.matches(in: html, options: [], range: range)
                
                Logger.debug("Pattern matched \(matches.count) times: \(pattern.prefix(50))...", category: .spotify)
                
                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: html),
                       let artistRange = Range(match.range(at: 2), in: html) {
                        let name = decodeHTMLEntities(String(html[nameRange]))
                        let artist = decodeHTMLEntities(String(html[artistRange]))
                        
                        // Skip playlist name and common false positives
                        guard name != playlistName,
                              !name.isEmpty,
                              name.count > 1,
                              !name.lowercased().contains("spotify"),
                              !name.lowercased().contains("playlist"),
                              artist.count > 1,
                              !tracks.contains(where: { $0.name == name && $0.artist == artist }) else {
                            continue
                        }
                        
                        tracks.append(ScrapedTrack(
                            name: name,
                            artist: artist,
                            album: playlistName,
                            duration: 0,
                            artworkURL: nil
                        ))
                    }
                }
            }
            
            // If we found tracks with this pattern, stop trying others
            if !tracks.isEmpty {
                Logger.info("Found \(tracks.count) tracks using pattern", category: .spotify)
                break
            }
        }
        
        // If no tracks found via JSON patterns, try extracting from script data
        if tracks.isEmpty {
            Logger.debug("No tracks from JSON patterns, trying script data extraction", category: .spotify)
            tracks = try extractTracksFromScriptData(html: html, containerName: playlistName)
        }
        
        // If still no tracks, try main page as fallback
        if tracks.isEmpty {
            Logger.debug("No tracks from script data, trying main page fallback", category: .spotify)
            tracks = try await scrapeTracksFromMainPage(type: "playlist", id: id)
        }
        
        // Last resort: try the oembed API
        if tracks.isEmpty {
            Logger.debug("Trying oEmbed API fallback", category: .spotify)
            tracks = try await scrapeTracksFromOEmbed(type: "playlist", id: id, containerName: playlistName)
        }
        
        return (name: playlistName, tracks: tracks)
    }
    
    /// Extract tracks from embedded script/JSON data in the page
    private func extractTracksFromScriptData(html: String, containerName: String) throws -> [ScrapedTrack] {
        var tracks: [ScrapedTrack] = []
        
        Logger.debug("Extracting tracks from script data", category: .spotify)
        
        // Look for __NEXT_DATA__ script tag - Next.js apps embed data here
        if let startRange = html.range(of: #"<script id="__NEXT_DATA__" type="application/json">"#),
           let endRange = html.range(of: "</script>", range: startRange.upperBound..<html.endIndex) {
            
            let jsonString = String(html[startRange.upperBound..<endRange.lowerBound])
            Logger.debug("Found __NEXT_DATA__ JSON: \(jsonString.count) chars", category: .spotify)
            
            // Parse as JSON and navigate the structure
            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                // Log top-level keys for debugging
                Logger.debug("__NEXT_DATA__ top-level keys: \(json.keys.sorted())", category: .spotify)
                
                // Log props structure if available
                if let props = json["props"] as? [String: Any] {
                    Logger.debug("props keys: \(props.keys.sorted())", category: .spotify)
                    if let pageProps = props["pageProps"] as? [String: Any] {
                        Logger.debug("pageProps keys: \(pageProps.keys.sorted())", category: .spotify)
                    }
                }
                
                // Navigate to track items - structure: props.pageProps.state.data.entity.trackList
                tracks = extractTracksFromNextData(json: json, containerName: containerName)
                
                if !tracks.isEmpty {
                    Logger.info("Extracted \(tracks.count) tracks from __NEXT_DATA__", category: .spotify)
                    return tracks
                } else {
                    // Log a sample of the JSON to understand structure
                    let jsonPreview = String(jsonString.prefix(2000))
                    Logger.debug("__NEXT_DATA__ preview: \(jsonPreview)", category: .spotify)
                }
            }
        }
        
        // Fallback: Look for track items in any script with JSON-like content
        // Pattern: items array containing track objects
        let itemsPattern = #""items"\s*:\s*\[(.*?)\]"#
        if let regex = try? NSRegularExpression(pattern: itemsPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let itemsRange = Range(match.range(at: 1), in: html) {
            
            let itemsString = String(html[itemsRange])
            
            // Extract individual track objects with name and artists
            let trackObjPattern = #"\{"[^}]*"name"\s*:\s*"([^"]+)"[^}]*"artists"\s*:\s*\[\s*\{[^}]*"name"\s*:\s*"([^"]+)""#
            if let trackRegex = try? NSRegularExpression(pattern: trackObjPattern, options: []) {
                let matches = trackRegex.matches(in: itemsString, range: NSRange(itemsString.startIndex..., in: itemsString))
                
                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: itemsString),
                       let artistRange = Range(match.range(at: 2), in: itemsString) {
                        let name = decodeHTMLEntities(String(itemsString[nameRange]))
                        let artist = decodeHTMLEntities(String(itemsString[artistRange]))
                        
                        if !name.isEmpty && name.count > 1 && !tracks.contains(where: { $0.name == name }) {
                            tracks.append(ScrapedTrack(
                                name: name,
                                artist: artist,
                                album: containerName,
                                duration: 0,
                                artworkURL: nil
                            ))
                        }
                    }
                }
            }
        }
        
        return tracks
    }
    
    /// Navigate Next.js JSON structure to find track items
    private func extractTracksFromNextData(json: [String: Any], containerName: String) -> [ScrapedTrack] {
        var tracks: [ScrapedTrack] = []
        var playlistName = containerName
        
        // Try various paths where track data might be located
        let paths: [[String]] = [
            ["props", "pageProps", "state", "data", "entity", "trackList"],
            ["props", "pageProps", "state", "data", "entity", "tracks", "items"],
            ["props", "pageProps", "data", "entity", "trackList"],
            ["props", "pageProps", "data", "playlist", "tracks", "items"],
            ["props", "pageProps", "playlist", "tracks", "items"]
        ]
        
        // Try to get playlist name from entity
        if let entity = navigateJSON(json: json, path: ["props", "pageProps", "state", "data", "entity"]) as? [String: Any],
           let name = entity["name"] as? String {
            playlistName = name
            Logger.debug("Found playlist name from entity: \(playlistName)", category: .spotify)
        }
        
        for path in paths {
            if let items = navigateJSON(json: json, path: path) as? [[String: Any]] {
                Logger.debug("Found \(items.count) items at path: \(path.joined(separator: "."))", category: .spotify)
                
                for item in items {
                    // Handle both direct track objects and wrapped track objects
                    let trackObj = (item["track"] as? [String: Any]) ?? item
                    
                    // Spotify embed format uses "title" and "subtitle" instead of "name" and "artists"
                    if let title = trackObj["title"] as? String,
                       let subtitle = trackObj["subtitle"] as? String {
                        
                        // Get duration (in milliseconds)
                        let durationMs = trackObj["duration"] as? Double ?? 0
                        let duration = durationMs / 1000.0
                        
                        tracks.append(ScrapedTrack(
                            name: title,
                            artist: subtitle,
                            album: playlistName,
                            duration: duration,
                            artworkURL: nil
                        ))
                        continue
                    }
                    
                    // Also try standard format with "name" and "artists" array
                    if let name = trackObj["name"] as? String,
                       let artists = trackObj["artists"] as? [[String: Any]],
                       let firstArtist = artists.first,
                       let artistName = firstArtist["name"] as? String {
                        
                        // Get artwork if available
                        var artworkURL: URL?
                        if let album = trackObj["album"] as? [String: Any],
                           let images = album["images"] as? [[String: Any]],
                           let firstImage = images.first,
                           let urlString = firstImage["url"] as? String {
                            artworkURL = URL(string: urlString)
                        }
                        
                        // Get duration
                        let duration = (trackObj["duration_ms"] as? Double ?? 0) / 1000.0
                        
                        tracks.append(ScrapedTrack(
                            name: name,
                            artist: artistName,
                            album: playlistName,
                            duration: duration,
                            artworkURL: artworkURL
                        ))
                    }
                }
                
                if !tracks.isEmpty {
                    Logger.info("Extracted \(tracks.count) tracks from path: \(path.joined(separator: "."))", category: .spotify)
                    break
                }
            }
        }
        
        // If structured paths didn't work, recursively search for track-like objects
        if tracks.isEmpty {
            tracks = findTracksRecursively(in: json, containerName: playlistName)
        }
        
        return tracks
    }
    
    /// Navigate JSON using a path of keys
    private func navigateJSON(json: Any, path: [String]) -> Any? {
        var current: Any = json
        for key in path {
            if let dict = current as? [String: Any], let next = dict[key] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }
    
    /// Recursively search JSON for track-like objects
    private func findTracksRecursively(in json: Any, containerName: String, maxDepth: Int = 10) -> [ScrapedTrack] {
        guard maxDepth > 0 else { return [] }
        var tracks: [ScrapedTrack] = []
        
        if let dict = json as? [String: Any] {
            // Check if this looks like a track object
            if let name = dict["name"] as? String,
               let artists = dict["artists"] as? [[String: Any]],
               let firstArtist = artists.first,
               let artistName = firstArtist["name"] as? String,
               let type = dict["type"] as? String,
               type == "track" {
                
                let duration = (dict["duration_ms"] as? Double ?? 0) / 1000.0
                
                tracks.append(ScrapedTrack(
                    name: name,
                    artist: artistName,
                    album: containerName,
                    duration: duration,
                    artworkURL: nil
                ))
            }
            
            // Recursively search values
            for (_, value) in dict {
                tracks.append(contentsOf: findTracksRecursively(in: value, containerName: containerName, maxDepth: maxDepth - 1))
            }
        } else if let array = json as? [Any] {
            for item in array {
                tracks.append(contentsOf: findTracksRecursively(in: item, containerName: containerName, maxDepth: maxDepth - 1))
            }
        }
        
        // Deduplicate
        var seen = Set<String>()
        tracks = tracks.filter { track in
            let key = "\(track.name)|\(track.artist)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
        
        return tracks
    }
    
    private func parseAlbumFromEmbed(html: String, id: String) async throws -> (name: String, tracks: [ScrapedTrack]) {
        var albumName = "Spotify Album"
        var albumArtist = "Unknown Artist"
        var tracks: [ScrapedTrack] = []
        var artworkURL: URL?
        
        // Extract album name and artist from og:title
        if let titleMatch = html.range(of: #"<meta property="og:title" content="([^"]+)""#, options: .regularExpression) {
            let titleContent = String(html[titleMatch])
            if let contentRange = titleContent.range(of: #"content="([^"]+)""#, options: .regularExpression) {
                var title = String(html[contentRange])
                title = title.replacingOccurrences(of: "content=\"", with: "")
                title = title.replacingOccurrences(of: "\"", with: "")
                
                // Parse "Album Name - Album by Artist"
                if let byRange = title.range(of: " - Album by ") {
                    albumName = decodeHTMLEntities(String(title[..<byRange.lowerBound]))
                    albumArtist = decodeHTMLEntities(String(title[byRange.upperBound...]))
                } else {
                    albumName = decodeHTMLEntities(title)
                }
            }
        }
        
        // Extract artwork
        if let imageMatch = html.range(of: #"<meta property="og:image" content="([^"]+)""#, options: .regularExpression) {
            let imageContent = String(html[imageMatch])
            if let urlStart = imageContent.range(of: "content=\""),
               let urlEnd = imageContent.range(of: "\"", range: urlStart.upperBound..<imageContent.endIndex) {
                let urlString = String(imageContent[urlStart.upperBound..<urlEnd.lowerBound])
                artworkURL = URL(string: urlString)
            }
        }
        
        // Extract track names from JSON
        let trackPattern = #""name"\s*:\s*"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: trackPattern, options: []) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: range)
            
            var seenNames = Set<String>()
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: html) {
                    let name = decodeHTMLEntities(String(html[nameRange]))
                    
                    // Skip album name and common false positives
                    if name != albumName && !seenNames.contains(name) && name.count > 1 {
                        seenNames.insert(name)
                        tracks.append(ScrapedTrack(
                            name: name,
                            artist: albumArtist,
                            album: albumName,
                            duration: 0,
                            artworkURL: artworkURL
                        ))
                    }
                }
            }
        }
        
        // If no tracks found, try main page
        if tracks.isEmpty {
            tracks = try await scrapeTracksFromMainPage(type: "album", id: id)
        }
        
        return (name: albumName, tracks: tracks)
    }
    
    private func scrapeTracksFromMainPage(type: String, id: String) async throws -> [ScrapedTrack] {
        // Fallback: fetch the main page and extract tracks
        let mainURL = "https://open.spotify.com/\(type)/\(id)"
        
        guard let url = URL(string: mainURL) else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8) else {
            return []
        }
        
        var tracks: [ScrapedTrack] = []
        
        // Try to extract from the main page's embedded data
        let trackArtistPattern = #""name":"([^"]+)"[^}]*?"artists":\[\{"[^}]*"name":"([^"]+)""#
        
        if let regex = try? NSRegularExpression(pattern: trackArtistPattern, options: []) {
            let range = NSRange(html.startIndex..., in: html)
            let matches = regex.matches(in: html, options: [], range: range)
            
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: html),
                   let artistRange = Range(match.range(at: 2), in: html) {
                    let name = decodeHTMLEntities(String(html[nameRange]))
                    let artist = decodeHTMLEntities(String(html[artistRange]))
                    
                    guard !name.isEmpty,
                          name.count > 1,
                          !name.contains("Spotify"),
                          !tracks.contains(where: { $0.name == name && $0.artist == artist }) else {
                        continue
                    }
                    
                    tracks.append(ScrapedTrack(
                        name: name,
                        artist: artist,
                        album: type == "album" ? name : "Spotify Playlist",
                        duration: 0,
                        artworkURL: nil
                    ))
                }
            }
        }
        
        return tracks
    }
    
    /// Fallback: Use Spotify's oEmbed API to get basic info, then scrape individual tracks
    private func scrapeTracksFromOEmbed(type: String, id: String, containerName: String) async throws -> [ScrapedTrack] {
        let oembedURL = "https://open.spotify.com/oembed?url=https://open.spotify.com/\(type)/\(id)"
        
        guard let url = URL(string: oembedURL) else { return [] }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return []
            }
            
            // Parse oEmbed response - it contains an HTML snippet with track links
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let html = json["html"] as? String {
                
                // Extract track IDs from the iframe src or embedded content
                var trackIDs: [String] = []
                
                // Look for track IDs in the HTML
                let trackIDPattern = #"spotify\.com/(?:embed/)?track/([a-zA-Z0-9]+)"#
                if let regex = try? NSRegularExpression(pattern: trackIDPattern, options: []) {
                    let range = NSRange(html.startIndex..., in: html)
                    let matches = regex.matches(in: html, options: [], range: range)
                    
                    for match in matches {
                        if let idRange = Range(match.range(at: 1), in: html) {
                            let trackID = String(html[idRange])
                            if !trackIDs.contains(trackID) {
                                trackIDs.append(trackID)
                            }
                        }
                    }
                }
                
                // Fetch metadata for each track
                var tracks: [ScrapedTrack] = []
                for trackID in trackIDs.prefix(50) { // Limit to 50 tracks
                    do {
                        let track = try await scrapeTrack(id: trackID)
                        tracks.append(ScrapedTrack(
                            name: track.name,
                            artist: track.artist,
                            album: containerName,
                            duration: track.duration,
                            artworkURL: track.artworkURL
                        ))
                    } catch {
                        // Skip failed tracks
                        continue
                    }
                }
                
                return tracks
            }
        } catch {
            Logger.debug("oEmbed fallback failed: \(error)", category: .spotify)
        }
        
        return []
    }
    
    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&#x27;", "'"),
            ("&#x2F;", "/"),
            ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        return result
    }
    
    // MARK: - Download
    
    /// Download a track by finding it on YouTube and downloading the audio
    public func downloadTrack(
        _ track: ScrapedTrack,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> SpotifyDownloadResult {
        guard let ytExtractor = youtubeExtractor else {
            throw SpotifyExtractionError.noYouTubeExtractor
        }
        
        // Search YouTube for the track
        let searchQuery = track.searchQuery
        progressHandler?(0.1)
        
        // Search YouTube and get video ID
        let videoID = try await searchYouTubeForTrack(query: searchQuery)
        progressHandler?(0.3)
        
        // Download from YouTube
        let ytResult = try await ytExtractor.downloadAudio(
            videoID: videoID,
            quality: .high
        ) { progress in
            progressHandler?(0.3 + (progress * 0.6))
        }
        
        progressHandler?(1.0)
        
        return SpotifyDownloadResult(
            localURL: ytResult.localURL,
            title: track.name,
            artist: track.artist,
            album: track.album,
            duration: track.duration > 0 ? track.duration : (ytResult.duration ?? 0),
            albumArtURL: track.artworkURL
        )
    }
    
    /// Search YouTube for a matching video
    private func searchYouTubeForTrack(query: String) async throws -> String {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = "https://www.youtube.com/results?search_query=\(encodedQuery)+audio"
        
        guard let url = URL(string: searchURL) else {
            throw SpotifyExtractionError.extractionFailed("Invalid search URL")
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw SpotifyExtractionError.extractionFailed("Could not parse YouTube search results")
        }
        
        // Extract video ID from search results
        let pattern = #"\"videoId\":\"([a-zA-Z0-9_-]{11})\""#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let idRange = Range(match.range(at: 1), in: html) else {
            throw SpotifyExtractionError.extractionFailed("Could not find matching video on YouTube")
        }
        
        return String(html[idRange])
    }
}
