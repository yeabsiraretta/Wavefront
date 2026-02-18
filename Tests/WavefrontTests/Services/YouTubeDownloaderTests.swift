import XCTest
@testable import Wavefront

final class YouTubeDownloaderTests: XCTestCase {
    
    var downloader: YouTubeDownloader!
    
    override func setUpWithError() throws {
        downloader = try YouTubeDownloader()
    }
    
    override func tearDown() {
        downloader = nil
    }
    
    // MARK: - Video ID Extraction Tests
    
    func testExtractVideoIDFromStandardURL() async {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromShortURL() async {
        let url = "https://youtu.be/dQw4w9WgXcQ"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromEmbedURL() async {
        let url = "https://www.youtube.com/embed/dQw4w9WgXcQ"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromMobileURL() async {
        let url = "https://m.youtube.com/watch?v=dQw4w9WgXcQ"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromMusicURL() async {
        let url = "https://music.youtube.com/watch?v=dQw4w9WgXcQ"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromRawID() async {
        let videoID = await downloader.extractVideoID(from: "dQw4w9WgXcQ")
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromURLWithExtraParams() async {
        let url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120&list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertEqual(videoID, "dQw4w9WgXcQ")
    }
    
    func testExtractVideoIDFromInvalidURL() async {
        let url = "https://www.google.com"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertNil(videoID)
    }
    
    func testExtractVideoIDFromEmptyString() async {
        let videoID = await downloader.extractVideoID(from: "")
        
        XCTAssertNil(videoID)
    }
    
    func testExtractVideoIDFromMalformedURL() async {
        let url = "not a url at all"
        let videoID = await downloader.extractVideoID(from: url)
        
        XCTAssertNil(videoID)
    }
    
    func testExtractVideoIDFromShortInvalidID() async {
        // Too short to be a valid ID
        let videoID = await downloader.extractVideoID(from: "abc")
        
        XCTAssertNil(videoID)
    }
    
    // MARK: - Quality Tests
    
    func testQualityDescriptions() {
        XCTAssertEqual(YouTubeDownloader.Quality.low.description, "Low (128kbps)")
        XCTAssertEqual(YouTubeDownloader.Quality.medium.description, "Medium (192kbps)")
        XCTAssertEqual(YouTubeDownloader.Quality.high.description, "High (320kbps)")
    }
    
    func testQualityRawValues() {
        XCTAssertEqual(YouTubeDownloader.Quality.low.rawValue, "low")
        XCTAssertEqual(YouTubeDownloader.Quality.medium.rawValue, "medium")
        XCTAssertEqual(YouTubeDownloader.Quality.high.rawValue, "high")
    }
    
    func testAllQualityCases() {
        XCTAssertEqual(YouTubeDownloader.Quality.allCases.count, 3)
    }
    
    // MARK: - Download Directory Tests
    
    func testListDownloadsReturnsEmptyInitially() async throws {
        // Clear any existing downloads first
        try await downloader.clearAllDownloads()
        
        let downloads = try await downloader.listDownloads()
        
        XCTAssertEqual(downloads.count, 0)
    }
    
    // MARK: - Create Track Tests
    
    func testCreateTrackFromDownloadResult() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.m4a")
        
        let result = YouTubeDownloader.DownloadResult(
            localURL: tempURL,
            title: "Test Song",
            duration: 180.0,
            author: "Test Artist",
            album: "Test Album",
            thumbnailURL: nil
        )
        
        let track = await downloader.createTrack(from: result)
        
        XCTAssertEqual(track.title, "Test Song")
        XCTAssertEqual(track.artist, "Test Artist")
        XCTAssertEqual(track.album, "Test Album")
        XCTAssertEqual(track.duration, 180.0)
        XCTAssertEqual(track.sourceType, .local)
    }
    
    func testCreateTrackWithNilAuthor() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.m4a")
        
        let result = YouTubeDownloader.DownloadResult(
            localURL: tempURL,
            title: "Test Song",
            duration: nil,
            author: nil,
            album: nil,
            thumbnailURL: nil
        )
        
        let track = await downloader.createTrack(from: result)
        
        XCTAssertEqual(track.title, "Test Song")
        XCTAssertNil(track.artist)
        XCTAssertNil(track.duration)
        XCTAssertEqual(track.album, "YouTube Downloads") // Falls back to default
    }
}

// MARK: - YouTubeError Tests

final class YouTubeErrorTests: XCTestCase {
    
    func testErrorDescriptions() {
        XCTAssertEqual(YouTubeError.invalidURL.errorDescription, "Invalid YouTube URL")
        XCTAssertEqual(YouTubeError.videoNotFound.errorDescription, "Video not found")
        XCTAssertEqual(YouTubeError.downloadFailed.errorDescription, "Download failed")
        XCTAssertEqual(YouTubeError.conversionFailed.errorDescription, "Audio conversion failed")
        XCTAssertEqual(YouTubeError.invalidPath.errorDescription, "Invalid file path")
    }
    
    func testExtractionNotImplementedError() {
        let error = YouTubeError.extractionNotImplemented(message: "Custom message")
        XCTAssertEqual(error.errorDescription, "Custom message")
    }
}

// MARK: - YouTubeVideoInfo Tests

final class YouTubeVideoInfoTests: XCTestCase {
    
    func testVideoInfoCreation() {
        let info = YouTubeVideoInfo(
            videoID: "abc123",
            title: "Test Video",
            author: "Test Channel",
            thumbnailURL: URL(string: "https://example.com/thumb.jpg")
        )
        
        XCTAssertEqual(info.videoID, "abc123")
        XCTAssertEqual(info.title, "Test Video")
        XCTAssertEqual(info.author, "Test Channel")
        XCTAssertNotNil(info.thumbnailURL)
    }
    
    func testVideoInfoWithNilOptionals() {
        let info = YouTubeVideoInfo(
            videoID: "abc123",
            title: "Test Video",
            author: nil,
            thumbnailURL: nil
        )
        
        XCTAssertNil(info.author)
        XCTAssertNil(info.thumbnailURL)
    }
}
