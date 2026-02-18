import XCTest
@testable import Wavefront

final class SMBConfigurationTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitWithAllProperties() {
        let serverURL = URL(string: "smb://192.168.1.100")!
        
        let config = SMBConfiguration(
            serverURL: serverURL,
            shareName: "music",
            username: "user",
            password: "pass",
            basePath: "/audio/library"
        )
        
        XCTAssertEqual(config.serverURL, serverURL)
        XCTAssertEqual(config.shareName, "music")
        XCTAssertEqual(config.username, "user")
        XCTAssertEqual(config.password, "pass")
        XCTAssertEqual(config.basePath, "/audio/library")
    }
    
    func testInitWithDefaults() {
        let serverURL = URL(string: "smb://192.168.1.100")!
        
        let config = SMBConfiguration(
            serverURL: serverURL,
            shareName: "music"
        )
        
        XCTAssertEqual(config.username, "guest")
        XCTAssertEqual(config.password, "")
        XCTAssertEqual(config.basePath, "/")
    }
    
    // MARK: - URL String Parsing Tests
    
    func testFromURLStringWithFullURL() {
        let config = SMBConfiguration.from(urlString: "smb://user:pass@192.168.1.100/share/path/to/music")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.serverURL.host, "192.168.1.100")
        XCTAssertEqual(config?.shareName, "share")
        XCTAssertEqual(config?.username, "user")
        XCTAssertEqual(config?.password, "pass")
        XCTAssertEqual(config?.basePath, "/path/to/music")
    }
    
    func testFromURLStringWithMinimalURL() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100/share")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.serverURL.host, "192.168.1.100")
        XCTAssertEqual(config?.shareName, "share")
        XCTAssertEqual(config?.username, "guest")
        XCTAssertEqual(config?.password, "")
        XCTAssertEqual(config?.basePath, "/")
    }
    
    func testFromURLStringWithHostname() {
        let config = SMBConfiguration.from(urlString: "smb://nas.local/music")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.serverURL.host, "nas.local")
        XCTAssertEqual(config?.shareName, "music")
    }
    
    func testFromURLStringWithOnlyUsername() {
        let config = SMBConfiguration.from(urlString: "smb://admin@192.168.1.100/share")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.username, "admin")
        XCTAssertEqual(config?.password, "")
    }
    
    func testFromURLStringWithNestedPath() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100/share/music/lossless/jazz")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.shareName, "share")
        XCTAssertEqual(config?.basePath, "/music/lossless/jazz")
    }
    
    // MARK: - Invalid URL Tests
    
    func testFromURLStringWithInvalidScheme() {
        let config = SMBConfiguration.from(urlString: "http://192.168.1.100/share")
        XCTAssertNil(config)
    }
    
    func testFromURLStringWithNoHost() {
        let config = SMBConfiguration.from(urlString: "smb:///share")
        XCTAssertNil(config)
    }
    
    func testFromURLStringWithNoShare() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100")
        XCTAssertNil(config)
    }
    
    func testFromURLStringWithNoShareJustSlash() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100/")
        XCTAssertNil(config)
    }
    
    func testFromURLStringWithInvalidURL() {
        let config = SMBConfiguration.from(urlString: "not a url")
        XCTAssertNil(config)
    }
    
    func testFromURLStringWithEmptyString() {
        let config = SMBConfiguration.from(urlString: "")
        XCTAssertNil(config)
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        let serverURL = URL(string: "smb://192.168.1.100")!
        
        let config1 = SMBConfiguration(serverURL: serverURL, shareName: "music")
        let config2 = SMBConfiguration(serverURL: serverURL, shareName: "music")
        
        XCTAssertEqual(config1, config2)
    }
    
    func testInequalityWithDifferentShare() {
        let serverURL = URL(string: "smb://192.168.1.100")!
        
        let config1 = SMBConfiguration(serverURL: serverURL, shareName: "music")
        let config2 = SMBConfiguration(serverURL: serverURL, shareName: "video")
        
        XCTAssertNotEqual(config1, config2)
    }
    
    func testInequalityWithDifferentServer() {
        let config1 = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.100")!,
            shareName: "music"
        )
        let config2 = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.101")!,
            shareName: "music"
        )
        
        XCTAssertNotEqual(config1, config2)
    }
}
