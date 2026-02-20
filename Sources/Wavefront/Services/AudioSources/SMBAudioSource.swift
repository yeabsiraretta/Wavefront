import Foundation
import AMSMB2

/// Actor to manage SMB client state safely
private actor SMBClientManager {
    private var client: SMB2Manager?
    
    func getClient() -> SMB2Manager? { client }
    func setClient(_ newClient: SMB2Manager?) { client = newClient }
}

/// Audio source for SMB network shares
public final class SMBAudioSource: AudioSource, @unchecked Sendable {
    public let sourceId: String
    public let displayName: String
    public let sourceType: AudioSourceType = .smb
    
    private let configuration: SMBConfiguration
    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let clientManager = SMBClientManager()
    
    public var isAvailable: Bool {
        get async {
            do {
                _ = try await connect()
                return true
            } catch {
                return false
            }
        }
    }
    
    public init(
        sourceId: String? = nil,
        displayName: String? = nil,
        configuration: SMBConfiguration,
        fileManager: FileManager = .default
    ) throws {
        self.configuration = configuration
        self.fileManager = fileManager
        self.sourceId = sourceId ?? "smb-\(configuration.serverURL.host ?? "unknown")-\(configuration.shareName)"
        self.displayName = displayName ?? "\(configuration.shareName) on \(configuration.serverURL.host ?? "SMB")"
        
        // Create cache directory for downloaded files
        let cachesURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.cacheDirectory = cachesURL.appendingPathComponent("SMBCache/\(self.sourceId)")
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    public func fetchTracks() async throws -> [AudioTrack] {
        try await fetchTracks(at: configuration.basePath)
    }
    
    public func fetchTracks(at path: String) async throws -> [AudioTrack] {
        let client = try await connect()
        return try await scanSMBDirectory(client: client, at: path)
    }
    
    public func getPlayableURL(for track: AudioTrack) async throws -> URL {
        guard track.sourceType == .smb else {
            throw AudioSourceError.trackNotFound("Track is not from SMB source")
        }
        
        // Check if file is already cached
        let cachedURL = cacheURL(for: track)
        if fileManager.fileExists(atPath: cachedURL.path) {
            return cachedURL
        }
        
        // Download file to cache
        let client = try await connect()
        let remotePath = extractRemotePath(from: track.fileURL)
        
        do {
            let data = try await client.contents(atPath: remotePath)
            try data.write(to: cachedURL)
            return cachedURL
        } catch {
            throw AudioSourceError.downloadFailed(error.localizedDescription)
        }
    }
    
    public func trackExists(_ track: AudioTrack) async -> Bool {
        guard track.sourceType == .smb else { return false }
        
        do {
            let client = try await connect()
            let remotePath = extractRemotePath(from: track.fileURL)
            let info = try await client.attributesOfItem(atPath: remotePath)
            return info[.fileSizeKey] != nil
        } catch {
            return false
        }
    }
    
    /// Clears the local cache for this SMB source
    public func clearCache() throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Disconnects from the SMB share
    public func disconnect() async {
        if let client = await clientManager.getClient() {
            try? await client.disconnectShare()
            await clientManager.setClient(nil)
        }
    }
    
    // MARK: - Private Methods
    
    private func connect() async throws -> SMB2Manager {
        // Check for existing client
        if let existingClient = await clientManager.getClient() {
            return existingClient
        }
        
        let credential = URLCredential(
            user: configuration.username,
            password: configuration.password,
            persistence: .forSession
        )
        
        guard let newClient = SMB2Manager(url: configuration.serverURL, credential: credential) else {
            throw AudioSourceError.connectionFailed("Failed to create SMB client")
        }
        
        do {
            try await newClient.connectShare(name: configuration.shareName)
        } catch {
            throw AudioSourceError.connectionFailed(error.localizedDescription)
        }
        
        await clientManager.setClient(newClient)
        
        return newClient
    }
    
    private func scanSMBDirectory(
        client: SMB2Manager,
        at path: String,
        recursive: Bool = true
    ) async throws -> [AudioTrack] {
        var tracks: [AudioTrack] = []
        
        let contents: [[URLResourceKey: Any]]
        do {
            contents = try await client.contentsOfDirectory(atPath: path)
        } catch {
            throw AudioSourceError.invalidPath(path)
        }
        
        for entry in contents {
            guard let name = entry[.nameKey] as? String,
                  let resourceType = entry[.fileResourceTypeKey] as? URLFileResourceType,
                  let entryPath = entry[.pathKey] as? String else {
                continue
            }
            
            if resourceType == .directory && recursive {
                // Skip hidden directories
                if name.hasPrefix(".") { continue }
                
                do {
                    let subTracks = try await scanSMBDirectory(client: client, at: entryPath, recursive: true)
                    tracks.append(contentsOf: subTracks)
                } catch {
                    // Continue on subdirectory errors
                    continue
                }
            } else if resourceType == .regular {
                guard AudioFormat.isSupported((name as NSString).pathExtension) else { continue }
                
                let track = createTrack(from: entry, path: entryPath)
                tracks.append(track)
            }
        }
        
        return tracks
    }
    
    private func createTrack(from entry: [URLResourceKey: Any], path: String) -> AudioTrack {
        let name = entry[.nameKey] as? String ?? "Unknown"
        let fileSize = entry[.fileSizeKey] as? Int64
        let creationDate = entry[.creationDateKey] as? Date ?? Date()
        
        // Build SMB URL for the track
        let smbURL = URL(string: "smb://\(configuration.serverURL.host ?? "")/\(configuration.shareName)\(path)")!
        
        // Extract title from filename (without extension)
        let title = (name as NSString).deletingPathExtension
        
        return AudioTrack(
            title: title,
            artist: nil,  // Would need to download file to extract metadata
            album: nil,
            duration: nil,
            fileURL: smbURL,
            sourceType: .smb,
            fileSize: fileSize,
            dateAdded: creationDate
        )
    }
    
    private func cacheURL(for track: AudioTrack) -> URL {
        let filename = track.fileURL.lastPathComponent
        let trackCacheDir = cacheDirectory.appendingPathComponent(track.id.uuidString)
        
        try? fileManager.createDirectory(at: trackCacheDir, withIntermediateDirectories: true)
        
        return trackCacheDir.appendingPathComponent(filename)
    }
    
    private func extractRemotePath(from url: URL) -> String {
        // Remove the scheme and host to get the path
        // smb://host/share/path -> /path
        var path = url.path
        
        // Remove the share name from the beginning of the path
        let sharePrefix = "/\(configuration.shareName)"
        if path.hasPrefix(sharePrefix) {
            path = String(path.dropFirst(sharePrefix.count))
        }
        
        return path.isEmpty ? "/" : path
    }
}
