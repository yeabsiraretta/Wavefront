import Foundation

/// Protocol defining the interface for audio sources
public protocol AudioSource: Sendable {
    /// Unique identifier for this source
    var sourceId: String { get }
    
    /// Human-readable name for the source
    var displayName: String { get }
    
    /// The type of this audio source
    var sourceType: AudioSourceType { get }
    
    /// Whether the source is currently available/connected
    var isAvailable: Bool { get async }
    
    /// Fetches all audio tracks from the source
    func fetchTracks() async throws -> [AudioTrack]
    
    /// Fetches audio tracks from a specific path within the source
    func fetchTracks(at path: String) async throws -> [AudioTrack]
    
    /// Gets a playable URL for the given track
    /// For local sources, this returns the file URL directly
    /// For remote sources, this may download/cache the file first
    func getPlayableURL(for track: AudioTrack) async throws -> URL
    
    /// Checks if a track exists in this source
    func trackExists(_ track: AudioTrack) async -> Bool
}

/// Errors that can occur when working with audio sources
public enum AudioSourceError: Error, LocalizedError, Equatable {
    case sourceUnavailable
    case trackNotFound(String)
    case connectionFailed(String)
    case authenticationFailed
    case permissionDenied
    case invalidPath(String)
    case downloadFailed(String)
    case unsupportedFormat(String)
    case timeout
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            return "Audio source is not available"
        case .trackNotFound(let path):
            return "Track not found: \(path)"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .authenticationFailed:
            return "Authentication failed"
        case .permissionDenied:
            return "Permission denied"
        case .invalidPath(let path):
            return "Invalid path: \(path)"
        case .downloadFailed(let reason):
            return "Download failed: \(reason)"
        case .unsupportedFormat(let format):
            return "Unsupported audio format: \(format)"
        case .timeout:
            return "Operation timed out"
        case .unknown(let reason):
            return "Unknown error: \(reason)"
        }
    }
}
