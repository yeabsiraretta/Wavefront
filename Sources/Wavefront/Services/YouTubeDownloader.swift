import Foundation
import AVFoundation

/// Service for downloading audio from YouTube videos
/// Uses Invidious API instances for audio extraction
public actor YouTubeDownloader {
    
    public enum Quality: String, CaseIterable, Sendable {
        case low = "low"
        case medium = "medium"
        case high = "high"
        
        public var description: String {
            switch self {
            case .low: return "Low (128kbps)"
            case .medium: return "Medium (192kbps)"
            case .high: return "High (320kbps)"
            }
        }
    }
    
    public struct DownloadResult: Sendable {
        public let localURL: URL
        public let title: String
        public let duration: TimeInterval?
        public let author: String?
        public let album: String?
        public let thumbnailURL: URL?
    }
    
    private let session: URLSession
    private let baseDirectory: URL
    private let fileManager: FileManager
    
    /// Invidious instances to try (public instances)
    private let invidiousInstances = [
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de",
        "https://invidious.privacyredirect.com",
        "https://invidious.protokolla.fi"
    ]
    
    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.session = URLSession.shared
        
        self.baseDirectory = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
    
    /// Get or create album directory for organizing downloads
    private func getAlbumDirectory(artist: String?, album: String?) throws -> URL {
        let artistName = sanitizeFilename(artist ?? "Unknown Artist")
        let albumName = sanitizeFilename(album ?? "YouTube Downloads")
        
        let albumDir = baseDirectory
            .appendingPathComponent("Music")
            .appendingPathComponent(artistName)
            .appendingPathComponent(albumName)
        
        try fileManager.createDirectory(at: albumDir, withIntermediateDirectories: true)
        return albumDir
    }
    
    /// Extract video ID from various YouTube URL formats
    public func extractVideoID(from urlString: String) -> String? {
        // Handle various YouTube URL formats
        let patterns = [
            // Standard watch URL: youtube.com/watch?v=VIDEO_ID
            "(?:youtube\\.com/watch\\?v=)([a-zA-Z0-9_-]{11})",
            // Short URL: youtu.be/VIDEO_ID
            "(?:youtu\\.be/)([a-zA-Z0-9_-]{11})",
            // Embed URL: youtube.com/embed/VIDEO_ID
            "(?:youtube\\.com/embed/)([a-zA-Z0-9_-]{11})",
            // Mobile URL: m.youtube.com/watch?v=VIDEO_ID
            "(?:m\\.youtube\\.com/watch\\?v=)([a-zA-Z0-9_-]{11})",
            // YouTube Music: music.youtube.com/watch?v=VIDEO_ID
            "(?:music\\.youtube\\.com/watch\\?v=)([a-zA-Z0-9_-]{11})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        
        // Check if it's already just a video ID
        if urlString.count == 11, urlString.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil {
            return urlString
        }
        
        return nil
    }
    
    /// Fetch video info from YouTube
    public func fetchVideoInfo(videoID: String) async throws -> YouTubeVideoInfo {
        // Use YouTube's oEmbed API for basic info
        let oembedURL = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json")!
        
        let (data, response) = try await session.data(from: oembedURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouTubeError.videoNotFound
        }
        
        let oembed = try JSONDecoder().decode(YouTubeOEmbed.self, from: data)
        
        return YouTubeVideoInfo(
            videoID: videoID,
            title: oembed.title,
            author: oembed.author_name,
            thumbnailURL: URL(string: oembed.thumbnail_url)
        )
    }
    
    /// Download audio from a YouTube video using Invidious API
    public func downloadAudio(
        videoID: String,
        quality: Quality = .medium,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DownloadResult {
        
        // Try each Invidious instance until one works
        var lastError: Error = YouTubeError.downloadFailed
        
        for instance in invidiousInstances {
            do {
                return try await downloadFromInvidious(
                    instance: instance,
                    videoID: videoID,
                    quality: quality,
                    progressHandler: progressHandler
                )
            } catch {
                lastError = error
                continue
            }
        }
        
        throw lastError
    }
    
    /// Download from a specific Invidious instance
    private func downloadFromInvidious(
        instance: String,
        videoID: String,
        quality: Quality,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> DownloadResult {
        
        // Fetch video info from Invidious API
        let apiURL = URL(string: "\(instance)/api/v1/videos/\(videoID)")!
        let (data, response) = try await session.data(from: apiURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouTubeError.videoNotFound
        }
        
        let videoInfo = try JSONDecoder().decode(InvidiousVideo.self, from: data)
        
        // Find best audio format
        guard let audioFormat = selectAudioFormat(from: videoInfo.adaptiveFormats, quality: quality) else {
            throw YouTubeError.downloadFailed
        }
        
        guard let audioURL = URL(string: audioFormat.url) else {
            throw YouTubeError.invalidURL
        }
        
        // Determine album from video metadata
        let album = videoInfo.genre ?? "YouTube Downloads"
        
        // Create album directory
        let albumDir = try getAlbumDirectory(artist: videoInfo.author, album: album)
        let sanitizedTitle = sanitizeFilename(videoInfo.title)
        let fileExtension = audioFormat.container ?? "m4a"
        let destinationURL = albumDir.appendingPathComponent("\(sanitizedTitle).\(fileExtension)")
        
        // Check if already downloaded
        if fileManager.fileExists(atPath: destinationURL.path) {
            let duration = await getAudioDuration(url: destinationURL)
            return DownloadResult(
                localURL: destinationURL,
                title: videoInfo.title,
                duration: duration ?? TimeInterval(videoInfo.lengthSeconds),
                author: videoInfo.author,
                album: album,
                thumbnailURL: videoInfo.videoThumbnails.first.flatMap { URL(string: $0.url) }
            )
        }
        
        progressHandler?(0.1)
        
        // Download the audio file
        let (tempURL, downloadResponse) = try await session.download(from: audioURL)
        
        guard let httpDownloadResponse = downloadResponse as? HTTPURLResponse,
              httpDownloadResponse.statusCode == 200 else {
            throw YouTubeError.downloadFailed
        }
        
        progressHandler?(0.9)
        
        // Move to destination
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        progressHandler?(1.0)
        
        let duration = await getAudioDuration(url: destinationURL)
        
        return DownloadResult(
            localURL: destinationURL,
            title: videoInfo.title,
            duration: duration ?? TimeInterval(videoInfo.lengthSeconds),
            author: videoInfo.author,
            album: album,
            thumbnailURL: videoInfo.videoThumbnails.first.flatMap { URL(string: $0.url) }
        )
    }
    
    /// Select the best audio format based on quality preference
    private func selectAudioFormat(from formats: [InvidiousAdaptiveFormat], quality: Quality) -> InvidiousAdaptiveFormat? {
        let audioFormats = formats.filter { $0.type.hasPrefix("audio/") }
        
        guard !audioFormats.isEmpty else { return nil }
        
        // Sort by bitrate
        let sorted = audioFormats.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }
        
        switch quality {
        case .high:
            return sorted.first
        case .medium:
            return sorted.count > 1 ? sorted[sorted.count / 2] : sorted.first
        case .low:
            return sorted.last
        }
    }
    
    /// Download from a direct audio URL (for use with backend extraction services)
    public func downloadFromDirectURL(
        url: URL,
        title: String,
        author: String?,
        album: String? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DownloadResult {
        
        let albumDir = try getAlbumDirectory(artist: author, album: album)
        let sanitizedTitle = sanitizeFilename(title)
        let destinationURL = albumDir.appendingPathComponent("\(sanitizedTitle).m4a")
        
        // Check if already downloaded
        if fileManager.fileExists(atPath: destinationURL.path) {
            let duration = await getAudioDuration(url: destinationURL)
            return DownloadResult(
                localURL: destinationURL,
                title: title,
                duration: duration,
                author: author,
                album: album,
                thumbnailURL: nil
            )
        }
        
        // Download the file
        let (tempURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw YouTubeError.downloadFailed
        }
        
        // Move to destination
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: tempURL, to: destinationURL)
        
        let duration = await getAudioDuration(url: destinationURL)
        
        return DownloadResult(
            localURL: destinationURL,
            title: title,
            duration: duration,
            author: author,
            album: album,
            thumbnailURL: nil
        )
    }
    
    /// Create an AudioTrack from a download result
    public func createTrack(from result: DownloadResult) -> AudioTrack {
        AudioTrack(
            title: result.title,
            artist: result.author,
            album: result.album ?? "YouTube Downloads",
            duration: result.duration,
            fileURL: result.localURL,
            sourceType: .local,
            fileSize: nil,
            dateAdded: Date()
        )
    }
    
    /// List all downloaded tracks in Music directory
    public func listDownloads() throws -> [URL] {
        let musicDir = baseDirectory.appendingPathComponent("Music")
        guard fileManager.fileExists(atPath: musicDir.path) else { return [] }
        
        var results: [URL] = []
        if let enumerator = fileManager.enumerator(at: musicDir, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator {
                if AudioFormat.isSupported(url.pathExtension) {
                    results.append(url)
                }
            }
        }
        return results
    }
    
    /// Delete a downloaded file
    public func deleteDownload(at url: URL) throws {
        let musicDir = baseDirectory.appendingPathComponent("Music")
        guard url.path.hasPrefix(musicDir.path) else {
            throw YouTubeError.invalidPath
        }
        try fileManager.removeItem(at: url)
    }
    
    /// Clear all downloads
    public func clearAllDownloads() throws {
        let downloads = try listDownloads()
        for url in downloads {
            try fileManager.removeItem(at: url)
        }
    }
    
    // MARK: - Private Helpers
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func getAudioDuration(url: URL) async -> TimeInterval? {
        let asset = AVAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds
        } catch {
            return nil
        }
    }
}

// MARK: - Models

public struct YouTubeVideoInfo: Sendable {
    public let videoID: String
    public let title: String
    public let author: String?
    public let thumbnailURL: URL?
}

struct YouTubeOEmbed: Codable {
    let title: String
    let author_name: String
    let thumbnail_url: String
}

// MARK: - Invidious API Models

struct InvidiousVideo: Codable {
    let title: String
    let videoId: String
    let author: String
    let lengthSeconds: Int
    let genre: String?
    let adaptiveFormats: [InvidiousAdaptiveFormat]
    let videoThumbnails: [InvidiousThumbnail]
    
    enum CodingKeys: String, CodingKey {
        case title, videoId, author, lengthSeconds, genre, adaptiveFormats, videoThumbnails
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        videoId = try container.decode(String.self, forKey: .videoId)
        author = try container.decode(String.self, forKey: .author)
        lengthSeconds = try container.decode(Int.self, forKey: .lengthSeconds)
        genre = try container.decodeIfPresent(String.self, forKey: .genre)
        adaptiveFormats = try container.decodeIfPresent([InvidiousAdaptiveFormat].self, forKey: .adaptiveFormats) ?? []
        videoThumbnails = try container.decodeIfPresent([InvidiousThumbnail].self, forKey: .videoThumbnails) ?? []
    }
}

struct InvidiousAdaptiveFormat: Codable {
    let url: String
    let type: String
    let bitrate: Int?
    let container: String?
    let encoding: String?
    
    enum CodingKeys: String, CodingKey {
        case url, type, bitrate, container, encoding
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        type = try container.decode(String.self, forKey: .type)
        bitrate = try container.decodeIfPresent(Int.self, forKey: .bitrate)
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
    }
}

struct InvidiousThumbnail: Codable {
    let url: String
    let quality: String?
}

// MARK: - Errors

public enum YouTubeError: Error, LocalizedError {
    case invalidURL
    case videoNotFound
    case extractionNotImplemented(message: String)
    case downloadFailed
    case conversionFailed
    case invalidPath
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid YouTube URL"
        case .videoNotFound:
            return "Video not found"
        case .extractionNotImplemented(let message):
            return message
        case .downloadFailed:
            return "Download failed"
        case .conversionFailed:
            return "Audio conversion failed"
        case .invalidPath:
            return "Invalid file path"
        }
    }
}

// MARK: - YouTube Player Integration Protocol

/// Protocol for integrating with YouTube player/extraction libraries
public protocol YouTubeExtractor: Sendable {
    func extractAudioURL(videoID: String, quality: YouTubeDownloader.Quality) async throws -> URL
}

/// Extension to use custom extractor
extension YouTubeDownloader {
    /// Download using a custom extractor implementation
    public func downloadWithExtractor(
        videoID: String,
        extractor: any YouTubeExtractor,
        quality: Quality = .medium,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DownloadResult {
        
        let videoInfo = try await fetchVideoInfo(videoID: videoID)
        let audioURL = try await extractor.extractAudioURL(videoID: videoID, quality: quality)
        
        return try await downloadFromDirectURL(
            url: audioURL,
            title: videoInfo.title,
            author: videoInfo.author,
            progressHandler: progressHandler
        )
    }
}
