import Foundation

/**
 * Protocol defining the interface for audio sources.
 *
 * Audio sources represent different locations where audio files can be stored
 * and accessed, such as local device storage, SMB network shares, or cloud services.
 *
 * ## Requirements
 * Implementations must be Sendable for use with Swift concurrency.
 *
 * ## Implementing a Custom Source
 * ```swift
 * class MyAudioSource: AudioSource {
 *     var sourceId: String { "my-source" }
 *     var displayName: String { "My Source" }
 *     var sourceType: AudioSourceType { .local }
 *     var isAvailable: Bool { get async { true } }
 *     // ... implement remaining methods
 * }
 * ```
 */
public protocol AudioSource: Sendable {
    /**
     * Unique identifier for this source instance.
     * Used to distinguish between multiple sources of the same type.
     */
    var sourceId: String { get }
    
    /**
     * Human-readable name for display in the UI.
     */
    var displayName: String { get }
    
    /**
     * The type category of this audio source.
     */
    var sourceType: AudioSourceType { get }
    
    /**
     * Whether the source is currently available and connected.
     * For network sources, this may involve a connectivity check.
     */
    var isAvailable: Bool { get async }
    
    /**
     * Fetches all audio tracks from the source.
     *
     * @returns Array of AudioTrack objects found in the source
     * @throws AudioSourceError if fetching fails
     */
    func fetchTracks() async throws -> [AudioTrack]
    
    /**
     * Fetches audio tracks from a specific path within the source.
     *
     * @param path - The path within the source to search
     * @returns Array of AudioTrack objects found at the path
     * @throws AudioSourceError if the path is invalid or fetching fails
     */
    func fetchTracks(at path: String) async throws -> [AudioTrack]
    
    /**
     * Gets a playable URL for the given track.
     *
     * For local sources, returns the file URL directly.
     * For remote sources, may download/cache the file first.
     *
     * @param track - The AudioTrack to get a URL for
     * @returns A URL that can be used for playback
     * @throws AudioSourceError if the track cannot be accessed
     */
    func getPlayableURL(for track: AudioTrack) async throws -> URL
    
    /**
     * Checks if a track exists in this source.
     *
     * @param track - The AudioTrack to check
     * @returns true if the track exists and is accessible
     */
    func trackExists(_ track: AudioTrack) async -> Bool
}

/**
 * Errors that can occur when working with audio sources.
 *
 * @case sourceUnavailable - The source is not accessible
 * @case trackNotFound - The requested track does not exist
 * @case connectionFailed - Network connection failed
 * @case authenticationFailed - Credentials were rejected
 * @case permissionDenied - Access was denied
 * @case invalidPath - The specified path is invalid
 * @case downloadFailed - File download failed
 * @case unsupportedFormat - The audio format is not supported
 * @case timeout - The operation timed out
 * @case unknown - An unknown error occurred
 */
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
