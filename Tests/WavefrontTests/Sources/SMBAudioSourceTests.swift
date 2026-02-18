import XCTest
@testable import Wavefront

final class SMBAudioSourceTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testInitWithValidConfiguration() throws {
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.100")!,
            shareName: "music",
            username: "user",
            password: "pass"
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        XCTAssertEqual(source.sourceType, .smb)
        XCTAssertTrue(source.sourceId.contains("smb-"))
        XCTAssertTrue(source.displayName.contains("music"))
    }
    
    func testInitWithCustomSourceId() throws {
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://nas.local")!,
            shareName: "share"
        )
        
        let source = try SMBAudioSource(
            sourceId: "custom-id",
            displayName: "My NAS",
            configuration: config
        )
        
        XCTAssertEqual(source.sourceId, "custom-id")
        XCTAssertEqual(source.displayName, "My NAS")
    }
    
    func testSourceTypeIsSMB() throws {
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.1")!,
            shareName: "test"
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        XCTAssertEqual(source.sourceType, .smb)
    }
    
    // MARK: - Track Exists Tests
    
    func testTrackExistsReturnsFalseForLocalTrack() async throws {
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.1")!,
            shareName: "test"
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        let localTrack = AudioTrack(
            title: "Local Song",
            fileURL: URL(fileURLWithPath: "/local/song.mp3"),
            sourceType: .local
        )
        
        let exists = await source.trackExists(localTrack)
        XCTAssertFalse(exists)
    }
    
    // MARK: - Get Playable URL Tests
    
    func testGetPlayableURLThrowsForLocalTrack() async throws {
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.1")!,
            shareName: "test"
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        let localTrack = AudioTrack(
            title: "Local Song",
            fileURL: URL(fileURLWithPath: "/local/song.mp3"),
            sourceType: .local
        )
        
        do {
            _ = try await source.getPlayableURL(for: localTrack)
            XCTFail("Should throw error for local track")
        } catch let error as AudioSourceError {
            if case .trackNotFound = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    // MARK: - Cache Tests
    
    func testClearCacheDoesNotThrow() throws {
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://192.168.1.1")!,
            shareName: "test"
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        // Should not throw
        try source.clearCache()
    }
}

// MARK: - SMBConfiguration URL Parsing Tests (Extended)

final class SMBConfigurationURLParsingTests: XCTestCase {
    
    func testFromURLStringWithIPv4() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100/share")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.serverURL.host, "192.168.1.100")
    }
    
    func testFromURLStringWithHostname() {
        let config = SMBConfiguration.from(urlString: "smb://mynas.local/music")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.serverURL.host, "mynas.local")
    }
    
    func testFromURLStringWithPort() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100:445/share")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.serverURL.port, 445)
    }
    
    func testFromURLStringWithCredentials() {
        let config = SMBConfiguration.from(urlString: "smb://admin:secret@192.168.1.100/share")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.username, "admin")
        XCTAssertEqual(config?.password, "secret")
    }
    
    func testFromURLStringWithDeepPath() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100/share/music/library/flac")
        
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.shareName, "share")
        XCTAssertEqual(config?.basePath, "/music/library/flac")
    }
    
    func testFromURLStringWithSpecialCharactersInPath() {
        let config = SMBConfiguration.from(urlString: "smb://192.168.1.100/share/My%20Music")
        
        XCTAssertNotNil(config)
    }
}

// MARK: - Integration Tests (require actual SMB server)

final class SMBIntegrationTests: XCTestCase {
    
    // These tests require environment variables to be set
    // SMB_TEST_HOST, SMB_TEST_SHARE, SMB_TEST_USER, SMB_TEST_PASS
    
    var smbHost: String? {
        ProcessInfo.processInfo.environment["SMB_TEST_HOST"]
    }
    
    var smbShare: String? {
        ProcessInfo.processInfo.environment["SMB_TEST_SHARE"]
    }
    
    var smbUser: String? {
        ProcessInfo.processInfo.environment["SMB_TEST_USER"]
    }
    
    var smbPass: String? {
        ProcessInfo.processInfo.environment["SMB_TEST_PASS"]
    }
    
    var canRunIntegrationTests: Bool {
        smbHost != nil && smbShare != nil
    }
    
    func testConnectionToRealSMBServer() async throws {
        try XCTSkipUnless(canRunIntegrationTests, "SMB integration test requires environment variables")
        
        guard let host = smbHost, let share = smbShare else {
            XCTFail("Missing SMB test configuration")
            return
        }
        
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://\(host)")!,
            shareName: share,
            username: smbUser ?? "guest",
            password: smbPass ?? ""
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        let isAvailable = await source.isAvailable
        XCTAssertTrue(isAvailable, "Should be able to connect to SMB server")
    }
    
    func testFetchTracksFromRealSMBServer() async throws {
        try XCTSkipUnless(canRunIntegrationTests, "SMB integration test requires environment variables")
        
        guard let host = smbHost, let share = smbShare else {
            XCTFail("Missing SMB test configuration")
            return
        }
        
        let config = SMBConfiguration(
            serverURL: URL(string: "smb://\(host)")!,
            shareName: share,
            username: smbUser ?? "guest",
            password: smbPass ?? ""
        )
        
        let source = try SMBAudioSource(configuration: config)
        
        let tracks = try await source.fetchTracks()
        
        // Just verify we get some result without error
        XCTAssertNotNil(tracks)
        
        // All tracks should be SMB type
        for track in tracks {
            XCTAssertEqual(track.sourceType, .smb)
        }
    }
}
