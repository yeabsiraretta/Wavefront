import Foundation

/// Configuration for SMB server connection
public struct SMBConfiguration: Equatable, Sendable {
    public let serverURL: URL
    public let shareName: String
    public let username: String
    public let password: String
    public let basePath: String
    
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
    
    /// Creates configuration from SMB URL string (e.g., "smb://user:pass@192.168.1.1/share/path")
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
