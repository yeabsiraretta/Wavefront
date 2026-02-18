import XCTest
@testable import Wavefront

final class AudioSourceErrorTests: XCTestCase {
    
    // MARK: - Error Description Tests
    
    func testSourceUnavailableDescription() {
        let error = AudioSourceError.sourceUnavailable
        XCTAssertEqual(error.errorDescription, "Audio source is not available")
    }
    
    func testTrackNotFoundDescription() {
        let error = AudioSourceError.trackNotFound("/path/to/missing.mp3")
        XCTAssertEqual(error.errorDescription, "Track not found: /path/to/missing.mp3")
    }
    
    func testConnectionFailedDescription() {
        let error = AudioSourceError.connectionFailed("Network unreachable")
        XCTAssertEqual(error.errorDescription, "Connection failed: Network unreachable")
    }
    
    func testAuthenticationFailedDescription() {
        let error = AudioSourceError.authenticationFailed
        XCTAssertEqual(error.errorDescription, "Authentication failed")
    }
    
    func testPermissionDeniedDescription() {
        let error = AudioSourceError.permissionDenied
        XCTAssertEqual(error.errorDescription, "Permission denied")
    }
    
    func testInvalidPathDescription() {
        let error = AudioSourceError.invalidPath("/invalid/path")
        XCTAssertEqual(error.errorDescription, "Invalid path: /invalid/path")
    }
    
    func testDownloadFailedDescription() {
        let error = AudioSourceError.downloadFailed("Timeout")
        XCTAssertEqual(error.errorDescription, "Download failed: Timeout")
    }
    
    func testUnsupportedFormatDescription() {
        let error = AudioSourceError.unsupportedFormat("ogg")
        XCTAssertEqual(error.errorDescription, "Unsupported audio format: ogg")
    }
    
    func testTimeoutDescription() {
        let error = AudioSourceError.timeout
        XCTAssertEqual(error.errorDescription, "Operation timed out")
    }
    
    func testUnknownDescription() {
        let error = AudioSourceError.unknown("Something went wrong")
        XCTAssertEqual(error.errorDescription, "Unknown error: Something went wrong")
    }
    
    // MARK: - Equatable Tests
    
    func testEquality() {
        let error1 = AudioSourceError.sourceUnavailable
        let error2 = AudioSourceError.sourceUnavailable
        XCTAssertEqual(error1, error2)
    }
    
    func testEqualityWithAssociatedValues() {
        let error1 = AudioSourceError.trackNotFound("path")
        let error2 = AudioSourceError.trackNotFound("path")
        XCTAssertEqual(error1, error2)
    }
    
    func testInequalityWithDifferentCases() {
        let error1 = AudioSourceError.sourceUnavailable
        let error2 = AudioSourceError.authenticationFailed
        XCTAssertNotEqual(error1, error2)
    }
    
    func testInequalityWithDifferentAssociatedValues() {
        let error1 = AudioSourceError.trackNotFound("path1")
        let error2 = AudioSourceError.trackNotFound("path2")
        XCTAssertNotEqual(error1, error2)
    }
}
