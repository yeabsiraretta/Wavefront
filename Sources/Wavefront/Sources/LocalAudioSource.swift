import Foundation
import AVFoundation

/// Audio source for local device storage (Documents directory)
public final class LocalAudioSource: AudioSource, @unchecked Sendable {
    public let sourceId: String
    public let displayName: String
    public let sourceType: AudioSourceType = .local
    
    private let fileManager: FileManager
    public let baseDirectory: URL
    
    /// Whether this source uses a security-scoped bookmark (for user-selected folders)
    public let isSecurityScoped: Bool
    private var isAccessingSecurityScopedResource = false
    
    public var isAvailable: Bool {
        get async {
            fileManager.fileExists(atPath: baseDirectory.path)
        }
    }
    
    /// Initialize with the app's Documents directory
    public init(
        sourceId: String = "local-storage",
        displayName: String = "Local Storage",
        fileManager: FileManager = .default
    ) throws {
        self.sourceId = sourceId
        self.displayName = displayName
        self.fileManager = fileManager
        self.isSecurityScoped = false
        self.baseDirectory = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }
    
    /// Initialize with a custom base directory (useful for testing or user-selected folders)
    public init(
        sourceId: String,
        displayName: String,
        baseDirectory: URL,
        isSecurityScoped: Bool = false,
        fileManager: FileManager = .default
    ) {
        self.sourceId = sourceId
        self.displayName = displayName
        self.baseDirectory = baseDirectory
        self.isSecurityScoped = isSecurityScoped
        self.fileManager = fileManager
    }
    
    public func fetchTracks() async throws -> [AudioTrack] {
        try await fetchTracks(at: "")
    }
    
    public func fetchTracks(at path: String) async throws -> [AudioTrack] {
        // Start accessing security-scoped resource if needed
        if isSecurityScoped {
            _ = baseDirectory.startAccessingSecurityScopedResource()
        }
        defer {
            if isSecurityScoped {
                baseDirectory.stopAccessingSecurityScopedResource()
            }
        }
        
        let searchURL = path.isEmpty ? baseDirectory : baseDirectory.appendingPathComponent(path)
        
        guard fileManager.fileExists(atPath: searchURL.path) else {
            throw AudioSourceError.invalidPath(path)
        }
        
        return try await scanDirectory(at: searchURL)
    }
    
    public func getPlayableURL(for track: AudioTrack) async throws -> URL {
        guard track.sourceType == .local else {
            throw AudioSourceError.trackNotFound("Track is not from local source")
        }
        
        guard fileManager.fileExists(atPath: track.fileURL.path) else {
            throw AudioSourceError.trackNotFound(track.fileURL.path)
        }
        
        return track.fileURL
    }
    
    public func trackExists(_ track: AudioTrack) async -> Bool {
        guard track.sourceType == .local else { return false }
        return fileManager.fileExists(atPath: track.fileURL.path)
    }
    
    // MARK: - Private Methods
    
    private func scanDirectory(at url: URL, recursive: Bool = true) async throws -> [AudioTrack] {
        var tracks: [AudioTrack] = []
        
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: recursive ? [] : [.skipsSubdirectoryDescendants]
        ) else {
            throw AudioSourceError.invalidPath(url.path)
        }
        
        for case let fileURL as URL in enumerator {
            guard AudioFormat.isSupported(fileURL.pathExtension) else { continue }
            
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                
                if resourceValues.isDirectory == true { continue }
                
                let track = try await createTrack(from: fileURL, resourceValues: resourceValues)
                tracks.append(track)
            } catch {
                continue
            }
        }
        
        return tracks
    }
    
    private func createTrack(from url: URL, resourceValues: URLResourceValues) async throws -> AudioTrack {
        let metadata = await extractMetadata(from: url)
        
        return AudioTrack(
            title: metadata.title ?? url.deletingPathExtension().lastPathComponent,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            fileURL: url,
            sourceType: .local,
            fileSize: resourceValues.fileSize.map { Int64($0) },
            dateAdded: resourceValues.creationDate ?? Date()
        )
    }
    
    private func extractMetadata(from url: URL) async -> AudioMetadata {
        let asset = AVAsset(url: url)
        
        var title: String?
        var artist: String?
        var album: String?
        var duration: TimeInterval?
        
        do {
            let metadata = try await asset.load(.commonMetadata)
            duration = try await asset.load(.duration).seconds
            
            for item in metadata {
                guard let key = item.commonKey else { continue }
                
                switch key {
                case .commonKeyTitle:
                    title = try await item.load(.stringValue)
                case .commonKeyArtist:
                    artist = try await item.load(.stringValue)
                case .commonKeyAlbumName:
                    album = try await item.load(.stringValue)
                default:
                    break
                }
            }
        } catch {
            // Metadata extraction failed, use defaults
        }
        
        return AudioMetadata(title: title, artist: artist, album: album, duration: duration)
    }
}

private struct AudioMetadata {
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
}
