import Foundation

/// Backend-based YouTube service that communicates with the Wavefront API
public actor BackendYouTubeService {
    
    /// Backend API configuration
    public struct Configuration: Sendable {
        public let baseURL: URL
        public let timeout: TimeInterval
        
        public init(baseURL: URL, timeout: TimeInterval = 30) {
            self.baseURL = baseURL
            self.timeout = timeout
        }
        
        /// Default configuration using localhost
        public static var localhost: Configuration {
            Configuration(baseURL: URL(string: "http://localhost:8000")!)
        }
    }
    
    private let configuration: Configuration
    private let session: URLSession
    private let fileManager: FileManager
    private let downloadDirectory: URL
    
    public init(
        configuration: Configuration,
        fileManager: FileManager = .default
    ) throws {
        self.configuration = configuration
        self.fileManager = fileManager
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        self.session = URLSession(configuration: sessionConfig)
        
        self.downloadDirectory = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Music")
        
        try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - API Methods
    
    /// Get video information from backend
    public func getVideoInfo(url: String) async throws -> BackendVideoInfo {
        let endpoint = configuration.baseURL.appendingPathComponent("/api/v1/video/info")
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["url": url]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = try? JSONDecoder().decode(BackendErrorResponse.self, from: data)
            throw BackendError.apiError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?.detail ?? "Unknown error"
            )
        }
        
        return try JSONDecoder().decode(BackendVideoInfo.self, from: data)
    }
    
    /// Start a download on the backend
    public func startDownload(url: String, quality: String = "high") async throws -> String {
        let endpoint = configuration.baseURL.appendingPathComponent("/api/v1/download/start")
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["url": url, "quality": quality]
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BackendError.downloadFailed
        }
        
        let result = try JSONDecoder().decode(BackendDownloadResponse.self, from: data)
        return result.download_id
    }
    
    /// Check download status
    public func checkStatus(downloadId: String) async throws -> BackendDownloadStatus {
        let endpoint = configuration.baseURL
            .appendingPathComponent("/api/v1/download/status")
            .appendingPathComponent(downloadId)
        
        let (data, response) = try await session.data(from: endpoint)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BackendError.downloadNotFound
        }
        
        return try JSONDecoder().decode(BackendDownloadStatus.self, from: data)
    }
    
    /// Download the audio file from backend
    public func downloadFile(
        downloadId: String,
        title: String,
        artist: String?,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let endpoint = configuration.baseURL
            .appendingPathComponent("/api/v1/download/file")
            .appendingPathComponent(downloadId)
        
        // Create destination directory
        let artistDir = sanitizeFilename(artist ?? "Unknown Artist")
        let destDir = downloadDirectory.appendingPathComponent(artistDir)
        try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        let sanitizedTitle = sanitizeFilename(title)
        let destURL = destDir.appendingPathComponent("\(sanitizedTitle).m4a")
        
        // Check if already exists
        if fileManager.fileExists(atPath: destURL.path) {
            return destURL
        }
        
        // Download the file
        let (tempURL, response) = try await session.download(from: endpoint)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw BackendError.downloadFailed
        }
        
        // Move to destination
        if fileManager.fileExists(atPath: destURL.path) {
            try fileManager.removeItem(at: destURL)
        }
        try fileManager.moveItem(at: tempURL, to: destURL)
        
        return destURL
    }
    
    /// Full import flow: get info, start download, wait for completion, download file
    public func importVideo(
        url: String,
        quality: String = "high",
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async throws -> YouTubeDownloader.DownloadResult {
        
        progressHandler?(0.05)
        
        // Get video info
        let info = try await getVideoInfo(url: url)
        
        progressHandler?(0.1)
        
        // Start download on backend
        let downloadId = try await startDownload(url: url, quality: quality)
        
        progressHandler?(0.15)
        
        // Poll for completion
        var status = try await checkStatus(downloadId: downloadId)
        while status.status != "completed" && status.status != "failed" {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            status = try await checkStatus(downloadId: downloadId)
            
            // Update progress (0.15 to 0.85 for download)
            let downloadProgress = 0.15 + (status.progress * 0.7)
            progressHandler?(downloadProgress)
        }
        
        if status.status == "failed" {
            throw BackendError.apiError(
                statusCode: 500,
                message: status.error ?? "Download failed"
            )
        }
        
        progressHandler?(0.9)
        
        // Download the file to device
        let localURL = try await downloadFile(
            downloadId: downloadId,
            title: info.title,
            artist: info.author
        )
        
        progressHandler?(1.0)
        
        return YouTubeDownloader.DownloadResult(
            localURL: localURL,
            title: info.title,
            duration: TimeInterval(info.duration),
            author: info.author,
            album: nil,
            thumbnailURL: info.thumbnail_url.flatMap { URL(string: $0) }
        )
    }
    
    // MARK: - Helpers
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Models

public struct BackendVideoInfo: Codable, Sendable {
    public let video_id: String
    public let title: String
    public let author: String
    public let duration: Int
    public let thumbnail_url: String?
    public let description: String?
    public let upload_date: String?
    public let view_count: Int?
}

public struct BackendDownloadResponse: Codable, Sendable {
    public let download_id: String
    public let status: String
    public let message: String
}

public struct BackendDownloadStatus: Codable, Sendable {
    public let download_id: String
    public let status: String
    public let progress: Double
    public let title: String?
    public let error: String?
}

struct BackendErrorResponse: Codable {
    let detail: String
}

// MARK: - Errors

public enum BackendError: Error, LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case downloadFailed
    case downloadNotFound
    case serverUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .downloadFailed:
            return "Download failed"
        case .downloadNotFound:
            return "Download not found"
        case .serverUnavailable:
            return "Backend server is unavailable"
        }
    }
}

// MARK: - YouTubeExtractor Conformance

extension BackendYouTubeService: YouTubeExtractor {
    public func extractAudioURL(videoID: String, quality: YouTubeDownloader.Quality) async throws -> URL {
        // Start download and wait for it to complete
        let url = "https://www.youtube.com/watch?v=\(videoID)"
        let qualityString = quality.rawValue
        
        let downloadId = try await startDownload(url: url, quality: qualityString)
        
        // Poll for completion
        var status = try await checkStatus(downloadId: downloadId)
        while status.status != "completed" && status.status != "failed" {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            status = try await checkStatus(downloadId: downloadId)
        }
        
        if status.status == "failed" {
            throw BackendError.downloadFailed
        }
        
        // Return the download URL (for streaming from backend)
        return configuration.baseURL
            .appendingPathComponent("/api/v1/download/stream")
            .appendingPathComponent(downloadId)
    }
}
