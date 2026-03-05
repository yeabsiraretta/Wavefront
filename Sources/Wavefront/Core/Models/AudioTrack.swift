import Foundation

/**
 * Represents a single audio track with metadata.
 *
 * This is the core data model for audio files in the Wavefront app.
 * It contains all metadata about a track including title, artist,
 * album, duration, and file location.
 *
 * ## Properties
 * @property id - Unique identifier for the track
 * @property title - Display title of the track
 * @property artist - Artist name, if known
 * @property album - Album name, if known
 * @property duration - Track duration in seconds
 * @property fileURL - URL to the audio file
 * @property sourceType - Type of audio source (local, SMB, etc.)
 * @property fileSize - File size in bytes
 * @property dateAdded - Date the track was added to library
 */
public struct AudioTrack: Identifiable, Equatable, Hashable, Sendable {
    /// Unique identifier for the track
    public let id: UUID
    
    /// Display title of the track
    public let title: String
    
    /// Artist name, nil if unknown
    public let artist: String?
    
    /// Album name, nil if unknown
    public let album: String?
    
    /// Track duration in seconds, nil if unknown
    public let duration: TimeInterval?
    
    /// URL to the audio file (local path or network URL)
    public let fileURL: URL
    
    /// Type of audio source this track comes from
    public let sourceType: AudioSourceType
    
    /// File size in bytes, nil if unknown
    public let fileSize: Int64?
    
    /// Date the track was added to the library
    public let dateAdded: Date
    
    /// Lyrics text for the track, nil if unavailable
    public let lyrics: String?
    
    /// URL to album artwork image (local file or remote URL)
    public let artworkURL: URL?
    
    /**
     * Creates a new AudioTrack instance.
     *
     * @param id - Unique identifier (auto-generated if not provided)
     * @param title - Display title of the track
     * @param artist - Optional artist name
     * @param album - Optional album name
     * @param duration - Optional duration in seconds
     * @param fileURL - URL to the audio file
     * @param sourceType - Type of audio source
     * @param fileSize - Optional file size in bytes
     * @param dateAdded - Date added (defaults to current date)
     * @param lyrics - Optional lyrics text
     * @param artworkURL - Optional URL to album artwork
     */
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        fileURL: URL,
        sourceType: AudioSourceType,
        fileSize: Int64? = nil,
        dateAdded: Date = Date(),
        lyrics: String? = nil,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.sourceType = sourceType
        self.fileSize = fileSize
        self.dateAdded = dateAdded
        self.lyrics = lyrics
        self.artworkURL = artworkURL
    }
}

/**
 * Enumeration of supported audio source types.
 *
 * @case local - Files stored on the local device
 * @case smb - Files accessed via SMB/CIFS network share
 */
public enum AudioSourceType: String, Codable, Sendable {
    case local
    case smb
}

/**
 * Enumeration of supported audio file formats.
 *
 * The app supports common audio formats including lossy (MP3, AAC)
 * and lossless (FLAC, ALAC, WAV, AIFF) formats.
 *
 * @case mp3 - MPEG Audio Layer 3
 * @case m4a - MPEG-4 Audio (typically AAC)
 * @case aac - Advanced Audio Coding
 * @case wav - Waveform Audio File Format
 * @case aiff - Audio Interchange File Format
 * @case flac - Free Lossless Audio Codec
 * @case alac - Apple Lossless Audio Codec
 */
public enum AudioFormat: String, CaseIterable, Sendable {
    case mp3
    case m4a
    case aac
    case wav
    case aiff
    case flac
    case alac
    
    /**
     * Set of all supported file extensions.
     *
     * @returns Set of extension strings (lowercase, without dots)
     */
    public static var supportedExtensions: Set<String> {
        Set(allCases.map { $0.rawValue })
    }
    
    /**
     * Checks if a file extension is supported.
     *
     * @param pathExtension - The file extension to check (with or without dot)
     * @returns true if the format is supported
     */
    public static func isSupported(_ pathExtension: String) -> Bool {
        supportedExtensions.contains(pathExtension.lowercased())
    }
}
