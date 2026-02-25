import XCTest
@testable import Wavefront

final class SpotifyExtractorTests: XCTestCase {
    
    var extractor: SpotifyExtractor!
    
    override func setUp() async throws {
        extractor = try SpotifyExtractor()
    }
    
    override func tearDown() async throws {
        extractor = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitializationSucceeds() async throws {
        let extractor = try SpotifyExtractor()
        XCTAssertNotNil(extractor)
    }
    
    // MARK: - URL Parsing Tests
    
    func testParseTrackURL() async {
        let url = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT"
        let result = await extractor.parseURL(url)
        
        if case .track(let id) = result {
            XCTAssertEqual(id, "4cOdK2wGLETKBW3PvgPWqT")
        } else {
            XCTFail("Expected track URL type")
        }
    }
    
    func testParsePlaylistURL() async {
        let url = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        let result = await extractor.parseURL(url)
        
        if case .playlist(let id) = result {
            XCTAssertEqual(id, "37i9dQZF1DXcBWIGoYBM5M")
        } else {
            XCTFail("Expected playlist URL type")
        }
    }
    
    func testParseAlbumURL() async {
        let url = "https://open.spotify.com/album/5Z9iiGl2FcIfa3BMiv6OIw"
        let result = await extractor.parseURL(url)
        
        if case .album(let id) = result {
            XCTAssertEqual(id, "5Z9iiGl2FcIfa3BMiv6OIw")
        } else {
            XCTFail("Expected album URL type")
        }
    }
    
    func testParseTrackURLWithQueryParams() async {
        let url = "https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=abc123"
        let result = await extractor.parseURL(url)
        
        if case .track(let id) = result {
            XCTAssertEqual(id, "4cOdK2wGLETKBW3PvgPWqT")
        } else {
            XCTFail("Expected track URL type")
        }
    }
    
    func testParseSpotifyURI() async {
        let uri = "spotify:track:4cOdK2wGLETKBW3PvgPWqT"
        let result = await extractor.parseURL(uri)
        
        if case .track(let id) = result {
            XCTAssertEqual(id, "4cOdK2wGLETKBW3PvgPWqT")
        } else {
            XCTFail("Expected track URL type from URI")
        }
    }
    
    func testParseInvalidURL() async {
        let url = "https://example.com/not-spotify"
        let result = await extractor.parseURL(url)
        
        if case .invalid = result {
            // Expected
        } else {
            XCTFail("Expected invalid URL type")
        }
    }
    
    func testParseEmptyString() async {
        let result = await extractor.parseURL("")
        
        if case .invalid = result {
            // Expected
        } else {
            XCTFail("Expected invalid URL type for empty string")
        }
    }
    
    func testParseMalformedURL() async {
        let url = "not a url at all"
        let result = await extractor.parseURL(url)
        
        if case .invalid = result {
            // Expected
        } else {
            XCTFail("Expected invalid URL type")
        }
    }
    
    // MARK: - Error Tests
    
    func testSpotifyExtractionErrorDescriptions() {
        XCTAssertNotNil(SpotifyExtractionError.invalidURL.errorDescription)
        XCTAssertNotNil(SpotifyExtractionError.noYouTubeExtractor.errorDescription)
    }
    
    func testSpotifyExtractionErrorInvalidURL() {
        let error = SpotifyExtractionError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid Spotify URL")
    }
    
    func testSpotifyExtractionErrorNoYouTubeExtractor() {
        let error = SpotifyExtractionError.noYouTubeExtractor
        XCTAssertEqual(error.errorDescription, "YouTube extractor not available")
    }
    
    func testSpotifyExtractionErrorExtractionFailed() {
        let error = SpotifyExtractionError.extractionFailed("Test message")
        XCTAssertEqual(error.errorDescription, "Extraction failed: Test message")
    }
    
    func testSpotifyExtractionErrorNetworkError() {
        let underlyingError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Connection lost"])
        let error = SpotifyExtractionError.networkError(underlyingError)
        XCTAssertTrue(error.errorDescription?.contains("Connection lost") ?? false)
    }
    
    // MARK: - ScrapedTrack Tests
    
    func testScrapedTrackSearchQuery() {
        let track = SpotifyExtractor.ScrapedTrack(
            name: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            duration: 354.0,
            artworkURL: nil
        )
        
        XCTAssertEqual(track.searchQuery, "Queen - Bohemian Rhapsody")
    }
    
    func testScrapedTrackWithArtworkURL() {
        let artworkURL = URL(string: "https://i.scdn.co/image/abc123")
        let track = SpotifyExtractor.ScrapedTrack(
            name: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            duration: 180.0,
            artworkURL: artworkURL
        )
        
        XCTAssertEqual(track.artworkURL, artworkURL)
    }
    
    // MARK: - SpotifyURLType Tests
    
    func testSpotifyURLTypeEquality() {
        let track1 = SpotifyExtractor.SpotifyURLType.track(id: "abc123")
        let track2 = SpotifyExtractor.SpotifyURLType.track(id: "abc123")
        let track3 = SpotifyExtractor.SpotifyURLType.track(id: "xyz789")
        
        // Note: Enums with associated values need custom equality if not Equatable
        if case .track(let id1) = track1, case .track(let id2) = track2 {
            XCTAssertEqual(id1, id2)
        }
        
        if case .track(let id1) = track1, case .track(let id3) = track3 {
            XCTAssertNotEqual(id1, id3)
        }
    }
    
    // MARK: - SpotifyDownloadResult Tests
    
    func testSpotifyDownloadResultProperties() {
        let url = URL(fileURLWithPath: "/test/song.m4a")
        let artworkURL = URL(string: "https://example.com/art.jpg")
        
        let result = SpotifyExtractor.SpotifyDownloadResult(
            localURL: url,
            title: "Test Song",
            artist: "Test Artist",
            album: "Test Album",
            duration: 200.0,
            albumArtURL: artworkURL
        )
        
        XCTAssertEqual(result.localURL, url)
        XCTAssertEqual(result.title, "Test Song")
        XCTAssertEqual(result.artist, "Test Artist")
        XCTAssertEqual(result.album, "Test Album")
        XCTAssertEqual(result.duration, 200.0)
        XCTAssertEqual(result.albumArtURL, artworkURL)
    }
}
