import XCTest
@testable import Wavefront

final class YouTubeKitExtractorTests: XCTestCase {
    
    var extractor: YouTubeKitExtractor!
    
    override func setUp() async throws {
        extractor = try YouTubeKitExtractor()
    }
    
    override func tearDown() async throws {
        extractor = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationSucceeds() async throws {
        let extractor = try YouTubeKitExtractor()
        XCTAssertNotNil(extractor)
    }
    
    func testInitializationCreatesDownloadDirectory() async throws {
        let extractor = try YouTubeKitExtractor()
        XCTAssertNotNil(extractor)
        
        // Verify the Music directory exists in Documents
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let musicDir = documentsURL.appendingPathComponent("Music")
        
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: musicDir.path, isDirectory: &isDirectory)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDirectory.boolValue)
    }
    
    // MARK: - Quality Enum Tests
    
    func testQualityEnumValues() {
        XCTAssertEqual(YouTubeKitExtractor.Quality.low.rawValue, "low")
        XCTAssertEqual(YouTubeKitExtractor.Quality.medium.rawValue, "medium")
        XCTAssertEqual(YouTubeKitExtractor.Quality.high.rawValue, "high")
    }
    
    func testQualityAllCases() {
        let allCases = YouTubeKitExtractor.Quality.allCases
        XCTAssertEqual(allCases.count, 3)
        XCTAssertTrue(allCases.contains(.low))
        XCTAssertTrue(allCases.contains(.medium))
        XCTAssertTrue(allCases.contains(.high))
    }
    
    // MARK: - Error Tests
    
    func testYouTubeKitErrorDescriptions() {
        XCTAssertNotNil(YouTubeKitError.invalidURL.errorDescription)
        XCTAssertNotNil(YouTubeKitError.noAudioStream.errorDescription)
        XCTAssertNotNil(YouTubeKitError.downloadFailed.errorDescription)
    }
    
    func testYouTubeKitErrorInvalidURL() {
        let error = YouTubeKitError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid YouTube URL")
    }
    
    func testYouTubeKitErrorNoAudioStream() {
        let error = YouTubeKitError.noAudioStream
        XCTAssertEqual(error.errorDescription, "No audio stream available")
    }
    
    func testYouTubeKitErrorDownloadFailed() {
        let error = YouTubeKitError.downloadFailed
        XCTAssertEqual(error.errorDescription, "Download failed")
    }
    
    func testYouTubeKitErrorExtractionFailed() {
        let error = YouTubeKitError.extractionFailed("Test error")
        XCTAssertEqual(error.errorDescription, "Extraction failed: Test error")
    }
    
    // MARK: - DownloadResult Tests
    
    func testDownloadResultInitialization() {
        let url = URL(fileURLWithPath: "/test/audio.m4a")
        let thumbnailURL = URL(string: "https://example.com/thumb.jpg")
        let result = YouTubeKitExtractor.DownloadResult(
            localURL: url,
            title: "Test Video",
            duration: 180.0,
            author: "Test Author",
            album: "YouTube Downloads",
            thumbnailURL: thumbnailURL
        )
        
        XCTAssertEqual(result.localURL, url)
        XCTAssertEqual(result.title, "Test Video")
        XCTAssertEqual(result.author, "Test Author")
        XCTAssertEqual(result.album, "YouTube Downloads")
        XCTAssertEqual(result.duration, 180.0)
        XCTAssertEqual(result.thumbnailURL, thumbnailURL)
    }
    
    func testDownloadResultWithNilOptionals() {
        let url = URL(fileURLWithPath: "/test/audio.m4a")
        let result = YouTubeKitExtractor.DownloadResult(
            localURL: url,
            title: "Test Video",
            duration: nil,
            author: nil,
            album: nil,
            thumbnailURL: nil
        )
        
        XCTAssertNil(result.author)
        XCTAssertNil(result.album)
        XCTAssertNil(result.duration)
        XCTAssertNil(result.thumbnailURL)
    }
    
    // MARK: - Video ID Validation Tests
    
    func testExtractVideoIDFromStandardURL() async {
        // Standard YouTube URL format
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let videoID = await extractor.extractVideoID(from: url)
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromShortURL() async {
        let url = "https://youtu.be/dQw4w9WgXcQ"
        let videoID = await extractor.extractVideoID(from: url)
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromEmbedURL() async {
        let url = "https://www.youtube.com/embed/dQw4w9WgXcQ"
        let videoID = await extractor.extractVideoID(from: url)
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromMusicURL() async {
        let url = "https://music.youtube.com/watch?v=dQw4w9WgXcQ"
        let videoID = await extractor.extractVideoID(from: url)
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromPlainID() async {
        // Plain video IDs without URL format return nil (requires URL format)
        let videoID = await extractor.extractVideoID(from: "dQw4w9WgXcQ")
        // The extractor requires a valid URL format, plain IDs return nil
        XCTAssertNil(videoID)
    }
    
    func testExtractVideoIDFromInvalidURL() async {
        let videoID = await extractor.extractVideoID(from: "not-a-valid-url")
        XCTAssertNil(videoID)
    }
    
    func testExtractVideoIDFromEmptyString() async {
        let videoID = await extractor.extractVideoID(from: "")
        XCTAssertNil(videoID)
    }
}

// MARK: - Quality Selection Tests

extension YouTubeKitExtractorTests {
    
    func testQualityEnumCases() {
        // Verify all quality cases exist
        let cases = YouTubeKitExtractor.Quality.allCases
        XCTAssertTrue(cases.contains(.low))
        XCTAssertTrue(cases.contains(.medium))
        XCTAssertTrue(cases.contains(.high))
    }
}
