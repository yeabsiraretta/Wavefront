import XCTest
@testable import Wavefront

final class AudioFormatTests: XCTestCase {
    
    // MARK: - Supported Extensions Tests
    
    func testSupportedExtensionsContainsAllFormats() {
        let extensions = AudioFormat.supportedExtensions
        
        XCTAssertTrue(extensions.contains("mp3"))
        XCTAssertTrue(extensions.contains("m4a"))
        XCTAssertTrue(extensions.contains("aac"))
        XCTAssertTrue(extensions.contains("wav"))
        XCTAssertTrue(extensions.contains("aiff"))
        XCTAssertTrue(extensions.contains("flac"))
        XCTAssertTrue(extensions.contains("alac"))
    }
    
    func testSupportedExtensionsCount() {
        XCTAssertEqual(AudioFormat.supportedExtensions.count, 7)
    }
    
    // MARK: - isSupported Tests
    
    func testIsSupportedWithValidExtensions() {
        XCTAssertTrue(AudioFormat.isSupported("mp3"))
        XCTAssertTrue(AudioFormat.isSupported("m4a"))
        XCTAssertTrue(AudioFormat.isSupported("aac"))
        XCTAssertTrue(AudioFormat.isSupported("wav"))
        XCTAssertTrue(AudioFormat.isSupported("aiff"))
        XCTAssertTrue(AudioFormat.isSupported("flac"))
        XCTAssertTrue(AudioFormat.isSupported("alac"))
    }
    
    func testIsSupportedWithUppercaseExtensions() {
        XCTAssertTrue(AudioFormat.isSupported("MP3"))
        XCTAssertTrue(AudioFormat.isSupported("M4A"))
        XCTAssertTrue(AudioFormat.isSupported("WAV"))
    }
    
    func testIsSupportedWithMixedCaseExtensions() {
        XCTAssertTrue(AudioFormat.isSupported("Mp3"))
        XCTAssertTrue(AudioFormat.isSupported("FlAc"))
    }
    
    func testIsSupportedWithUnsupportedExtensions() {
        XCTAssertFalse(AudioFormat.isSupported("txt"))
        XCTAssertFalse(AudioFormat.isSupported("pdf"))
        XCTAssertFalse(AudioFormat.isSupported("jpg"))
        XCTAssertFalse(AudioFormat.isSupported("ogg"))  // OGG not supported in AVFoundation by default
        XCTAssertFalse(AudioFormat.isSupported("wma"))
    }
    
    func testIsSupportedWithEmptyString() {
        XCTAssertFalse(AudioFormat.isSupported(""))
    }
    
    func testIsSupportedWithDotPrefix() {
        // Extension should not include the dot
        XCTAssertFalse(AudioFormat.isSupported(".mp3"))
    }
    
    // MARK: - Raw Value Tests
    
    func testRawValues() {
        XCTAssertEqual(AudioFormat.mp3.rawValue, "mp3")
        XCTAssertEqual(AudioFormat.m4a.rawValue, "m4a")
        XCTAssertEqual(AudioFormat.aac.rawValue, "aac")
        XCTAssertEqual(AudioFormat.wav.rawValue, "wav")
        XCTAssertEqual(AudioFormat.aiff.rawValue, "aiff")
        XCTAssertEqual(AudioFormat.flac.rawValue, "flac")
        XCTAssertEqual(AudioFormat.alac.rawValue, "alac")
    }
    
    // MARK: - CaseIterable Tests
    
    func testAllCases() {
        XCTAssertEqual(AudioFormat.allCases.count, 7)
    }
}
