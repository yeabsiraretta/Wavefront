import Foundation

/**
 * Configuration model for SMB/CIFS server connections.
 *
 * Stores all necessary information to connect to an SMB network share,
 * including server address, credentials, and the target path.
 *
 * ## Properties
 * @property serverURL - Base URL of the SMB server (e.g., smb://192.168.1.1)
 * @property shareName - Name of the network share to connect to
 * @property username - Username for authentication (default: "guest")
 * @property password - Password for authentication (default: empty)
 * @property basePath - Path within the share to use as root (default: "/")
 *
 * ## Usage
 * ```swift
 * let config = SMBConfiguration(
 *     serverURL: URL(string: "smb://192.168.1.1")!,
 *     shareName: "Music",
 *     username: "user",
 *     password: "pass"
 * )
 * ```
 */
public struct SMBConfiguration: Equatable, Sendable {
    /// Base URL of the SMB server
    public let serverURL: URL
    
    /// Name of the network share
    public let shareName: String
    
    /// Username for authentication
    public let username: String
    
    /// Password for authentication
    public let password: String
    
    /// Base path within the share
    public let basePath: String
    
    /**
     * Creates a new SMBConfiguration with the specified parameters.
     *
     * @param serverURL - Base URL of the SMB server
     * @param shareName - Name of the network share
     * @param username - Username for auth (defaults to "guest")
     * @param password - Password for auth (defaults to empty)
     * @param basePath - Base path within share (defaults to "/")
     */
    public init(
        serverURL: URL,
        shareName: String,
        username: String = "guest",
        password: String = "",
        basePath: String = "/"
    ) {
        self.serverURL = serverURL
        self.shareName = shareName
        self.username = username
        self.password = password
        self.basePath = basePath
    }
    
    /**
     * Creates a configuration from an SMB URL string.
     *
     * Parses a full SMB URL including credentials and path components.
     * Example: "smb://user:pass@192.168.1.1/share/path"
     *
     * @param urlString - The SMB URL string to parse
     * @returns SMBConfiguration if parsing succeeds, nil otherwise
     */
    public static func from(urlString: String) -> SMBConfiguration? {
        guard let url = URL(string: urlString),
              url.scheme == "smb",
              let host = url.host else {
            return nil
        }
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard let shareName = pathComponents.first else {
            return nil
        }
        
        let basePath = "/" + pathComponents.dropFirst().joined(separator: "/")
        let serverURL = URL(string: "smb://\(host)")!
        
        return SMBConfiguration(
            serverURL: serverURL,
            shareName: shareName,
            username: url.user ?? "guest",
            password: url.password ?? "",
            basePath: basePath.isEmpty ? "/" : basePath
        )
    }
}
