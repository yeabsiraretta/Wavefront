import Foundation
import AVFoundation
import YouTubeKit

/**
 * Native YouTube audio extractor using YouTubeKit.
 *
 * Downloads audio from YouTube videos entirely in-process without
 * external dependencies. Supports video search, stream extraction,
 * and audio download with quality selection.
 *
 * ## Features
 * - Video metadata extraction
 * - Audio stream selection by quality
 * - Progressive download with progress reporting
 * - Automatic retry on network failures
 * - File organization by artist/album
 *
 * ## Usage
 * ```swift
 * let extractor = try YouTubeKitExtractor()
 * let result = try await extractor.downloadAudio(videoID: "dQw4w9WgXcQ")
 * ```
 *
 * @note This actor is thread-safe for concurrent access.
 */
public actor YouTubeKitExtractor {
    
    private let session: URLSession
    private let fileManager: FileManager
    private let downloadDirectory: URL
    
    /**
     * Initializes the YouTubeKitExtractor.
     *
     * Creates the download directory in the app's Documents folder
     * if it doesn't already exist.
     *
     * @param fileManager - FileManager instance to use
     * @throws Error if the download directory cannot be created
     */
    public init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.session = URLSession.shared
        
        self.downloadDirectory = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Music")
        
        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Extract and download audio from a YouTube video
    public func downloadAudio(
        videoID: String,
        quality: Quality = .high,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> DownloadResult {
        
        progressHandler?(0.05)
        
        // Create YouTube object and fetch streams
        let youtube = YouTube(videoID: videoID)
        
        let streams = try await youtube.streams
        let metadata = try await youtube.metadata
        
        progressHandler?(0.15)
        
        // Filter for audio-only streams, prefer m4a
        let audioStreams = streams.filterAudioOnly()
        
        guard let audioStream = selectBestAudioStream(from: audioStreams, quality: quality) else {
            throw YouTubeKitError.noAudioStream
        }
        
        progressHandler?(0.2)
        
        // Prepare destination
        let artist = "Unknown Artist"
        let title = metadata?.title ?? "Unknown Track"
        let album = "YouTube Downloads"
        
        let albumDir = try getAlbumDirectory(artist: artist, album: album)
        let sanitizedTitle = sanitizeFilename(title)
        let fileExtension = audioStream.fileExtension.rawValue
        let destinationURL = albumDir.appendingPathComponent("\(sanitizedTitle).\(fileExtension)")
        
        // Check if already downloaded
        if fileManager.fileExists(atPath: destinationURL.path) {
            let duration = await getAudioDuration(url: destinationURL)
            return DownloadResult(
                localURL: destinationURL,
                title: title,
                duration: duration,
                author: artist,
                album: album,
                thumbnailURL: metadata?.thumbnail?.url
            )
        }
        
        progressHandler?(0.25)
        
        // Download the audio file with retry logic
        let streamURL = audioStream.url
        let tempURL = try await downloadWithRetry(
            url: streamURL,
            maxRetries: 3,
            progressHandler: progressHandler
        )
        
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
            title: title,
            duration: duration,
            author: artist,
            album: album,
            thumbnailURL: metadata?.thumbnail?.url
        )
    }
    
    /// Extract video ID from various YouTube URL formats
    public func extractVideoID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        // Handle youtu.be format
        if url.host?.contains("youtu.be") == true {
            return url.pathComponents.last
        }
        
        // Handle youtube.com format
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Check for 'v' parameter
            if let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return videoID
            }
            
            // Handle /embed/ format
            if url.pathComponents.contains("embed"),
               let index = url.pathComponents.firstIndex(of: "embed"),
               url.pathComponents.count > index + 1 {
                return url.pathComponents[index + 1]
            }
            
            // Handle /v/ format
            if url.pathComponents.contains("v"),
               let index = url.pathComponents.firstIndex(of: "v"),
               url.pathComponents.count > index + 1 {
                return url.pathComponents[index + 1]
            }
        }
        
        return nil
    }
    
    /// Extract video IDs from a YouTube playlist URL
    /// Uses YouTube's playlist page to get video IDs
    public func extractPlaylistVideoIDs(from urlString: String) async -> [String] {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let listID = components.queryItems?.first(where: { $0.name == "list" })?.value else {
            return []
        }
        
        // Fetch playlist page and extract video IDs
        let playlistURL = "https://www.youtube.com/playlist?list=\(listID)"
        
        guard let pageURL = URL(string: playlistURL) else { return [] }
        
        do {
            let (data, _) = try await session.data(from: pageURL)
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            
            // Extract video IDs from playlist page
            var videoIDs: [String] = []
            let pattern = #"\"videoId\":\"([a-zA-Z0-9_-]{11})\""#
            
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(html.startIndex..., in: html)
                let matches = regex.matches(in: html, range: range)
                
                for match in matches {
                    if let idRange = Range(match.range(at: 1), in: html) {
                        let videoID = String(html[idRange])
                        if !videoIDs.contains(videoID) {
                            videoIDs.append(videoID)
                        }
                    }
                }
            }
            
            return videoIDs
        } catch {
            return []
        }
    }
    
    // MARK: - Private Methods
    
    private func selectBestAudioStream(from streams: [YouTubeKit.Stream], quality: Quality) -> YouTubeKit.Stream? {
        let m4aStreams = streams.filter { $0.fileExtension == YouTubeKit.FileExtension.m4a }
        let targetStreams = m4aStreams.isEmpty ? streams : m4aStreams
        
        guard !targetStreams.isEmpty else { return nil }
        
        // Use YouTubeKit's built-in helper methods for quality selection
        switch quality {
        case .high:
            return targetStreams.highestAudioBitrateStream()
        case .medium, .low:
            return targetStreams.lowestAudioBitrateStream()
        }
    }
    
    private func getAlbumDirectory(artist: String?, album: String?) throws -> URL {
        let artistFolder = sanitizeFilename(artist ?? "Unknown Artist")
        let albumFolder = sanitizeFilename(album ?? "Unknown Album")
        
        let albumDir = downloadDirectory
            .appendingPathComponent(artistFolder)
            .appendingPathComponent(albumFolder)
        
        try fileManager.createDirectory(at: albumDir, withIntermediateDirectories: true)
        return albumDir
    }
    
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
    
    /// Download with retry logic for transient network failures
    private func downloadWithRetry(
        url: URL,
        maxRetries: Int,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        var lastError: Error = YouTubeKitError.downloadFailed
        
        for attempt in 0..<maxRetries {
            do {
                // Update progress based on attempt
                let baseProgress = 0.25 + (Double(attempt) * 0.1)
                progressHandler?(min(baseProgress, 0.85))
                
                let (tempURL, response) = try await session.download(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    throw YouTubeKitError.downloadFailed
                }
                
                return tempURL
            } catch let error as URLError where isRetryableError(error) {
                lastError = error
                // Exponential backoff: 1s, 2s, 4s
                let delay = pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            } catch {
                throw error
            }
        }
        
        throw lastError
    }
    
    /// Check if error is retryable (transient network issues)
    private func isRetryableError(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,      // -1005
             .timedOut,                    // -1001
             .cannotConnectToHost,         // -1004
             .notConnectedToInternet,      // -1009
             .dataNotAllowed:              // -1020
            return true
        default:
            return false
        }
    }
    
    // MARK: - Types
    
    public enum Quality: String, CaseIterable, Sendable {
        case low = "low"
        case medium = "medium"
        case high = "high"
    }
    
    public struct DownloadResult: Sendable {
        public let localURL: URL
        public let title: String
        public let duration: TimeInterval?
        public let author: String?
        public let album: String?
        public let thumbnailURL: URL?
    }
}

// MARK: - Errors

public enum YouTubeKitError: Error, LocalizedError {
    case noAudioStream
    case downloadFailed
    case invalidURL
    case extractionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noAudioStream:
            return "No audio stream available"
        case .downloadFailed:
            return "Download failed"
        case .invalidURL:
            return "Invalid YouTube URL"
        case .extractionFailed(let message):
            return "Extraction failed: \(message)"
        }
    }
}
