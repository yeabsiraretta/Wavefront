import Foundation

/// Represents a single audio track with metadata
public struct AudioTrack: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let artist: String?
    public let album: String?
    public let duration: TimeInterval?
    public let fileURL: URL
    public let sourceType: AudioSourceType
    public let fileSize: Int64?
    public let dateAdded: Date
    
    public init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        fileURL: URL,
        sourceType: AudioSourceType,
        fileSize: Int64? = nil,
        dateAdded: Date = Date()
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
    }
}

/// Supported audio source types
public enum AudioSourceType: String, Codable, Sendable {
    case local
    case smb
}

/// Supported audio file formats
public enum AudioFormat: String, CaseIterable, Sendable {
    case mp3
    case m4a
    case aac
    case wav
    case aiff
    case flac
    case alac
    
    public static var supportedExtensions: Set<String> {
        Set(allCases.map { $0.rawValue })
    }
    
    public static func isSupported(_ pathExtension: String) -> Bool {
        supportedExtensions.contains(pathExtension.lowercased())
    }
}
