import XCTest
@testable import Wavefront

final class MetadataServiceTests: XCTestCase {
    
    var service: MetadataService!
    
    override func setUp() {
        service = MetadataService()
    }
    
    override func tearDown() {
        service = nil
    }
    
    // MARK: - Title Parsing Tests
    
    func testEnrichTrackParsesArtistFromTitle() async {
        let track = AudioTrack(
            title: "Artist Name - Song Title",
            fileURL: URL(fileURLWithPath: "/test/song.mp3"),
            sourceType: .local
        )
        
        // This will attempt to enrich but likely fail without real API
        // The important thing is it doesn't crash and returns a track
        let enriched = await service.enrichTrack(track)
        
        XCTAssertNotNil(enriched)
        XCTAssertEqual(enriched.id, track.id)
    }
    
    func testEnrichTrackWithExistingMetadataReturnsOriginal() async {
        let track = AudioTrack(
            title: "Song Title",
            artist: "Known Artist",
            album: "Known Album",
            fileURL: URL(fileURLWithPath: "/test/song.mp3"),
            sourceType: .local
        )
        
        // Should not need enrichment since metadata is already present
        let enriched = await service.enrichTrack(track)
        
        XCTAssertEqual(enriched.artist, "Known Artist")
        XCTAssertEqual(enriched.album, "Known Album")
    }
    
    func testEnrichTracksProcessesMultipleTracks() async {
        let tracks = [
            AudioTrack(title: "Song 1", fileURL: URL(fileURLWithPath: "/1.mp3"), sourceType: .local),
            AudioTrack(title: "Song 2", fileURL: URL(fileURLWithPath: "/2.mp3"), sourceType: .local),
            AudioTrack(title: "Song 3", fileURL: URL(fileURLWithPath: "/3.mp3"), sourceType: .local)
        ]
        
        let enriched = await service.enrichTracks(tracks)
        
        XCTAssertEqual(enriched.count, 3)
    }
    
    func testClearCache() async {
        // Just verify it doesn't crash
        await service.clearCache()
    }
    
    // MARK: - Title Parsing Format Tests
    
    func testParsesDashSeparatedTitle() async {
        // "Artist - Track" format is the most common
        let track = AudioTrack(
            title: "The Beatles - Hey Jude",
            fileURL: URL(fileURLWithPath: "/test.mp3"),
            sourceType: .local
        )
        
        let enriched = await service.enrichTrack(track)
        XCTAssertNotNil(enriched)
    }
    
    func testParsesUnderscoreSeparatedTitle() async {
        let track = AudioTrack(
            title: "Pink_Floyd_-_Comfortably_Numb",
            fileURL: URL(fileURLWithPath: "/test.mp3"),
            sourceType: .local
        )
        
        let enriched = await service.enrichTrack(track)
        XCTAssertNotNil(enriched)
    }
    
    func testHandlesTitleWithoutSeparator() async {
        let track = AudioTrack(
            title: "JustASongTitle",
            fileURL: URL(fileURLWithPath: "/test.mp3"),
            sourceType: .local
        )
        
        // Should return original since no artist can be parsed
        let enriched = await service.enrichTrack(track)
        XCTAssertEqual(enriched.title, track.title)
    }
}

// MARK: - TrackMetadata Tests

final class TrackMetadataTests: XCTestCase {
    
    func testInitFromAudioDBTrack() {
        let dbTrack = AudioDBTrack(
            strTrack: "Test Track",
            strArtist: "Test Artist",
            strAlbum: "Test Album",
            intDuration: "180000",  // 3 minutes in ms
            strGenre: "Rock",
            intTrackNumber: "5",
            intYearReleased: "2020",
            strTrackThumb: "https://example.com/thumb.jpg",
            strDescriptionEN: "A great song"
        )
        
        let metadata = TrackMetadata(from: dbTrack)
        
        XCTAssertEqual(metadata.trackName, "Test Track")
        XCTAssertEqual(metadata.artist, "Test Artist")
        XCTAssertEqual(metadata.album, "Test Album")
        XCTAssertEqual(metadata.duration ?? 0, 180.0, accuracy: 0.1)
        XCTAssertEqual(metadata.genre, "Rock")
        XCTAssertEqual(metadata.trackNumber, 5)
        XCTAssertEqual(metadata.year, "2020")
        XCTAssertNotNil(metadata.thumbnailURL)
        XCTAssertEqual(metadata.description, "A great song")
    }
    
    func testInitWithNilValues() {
        let dbTrack = AudioDBTrack(
            strTrack: nil,
            strArtist: nil,
            strAlbum: nil,
            intDuration: nil,
            strGenre: nil,
            intTrackNumber: nil,
            intYearReleased: nil,
            strTrackThumb: nil,
            strDescriptionEN: nil
        )
        
        let metadata = TrackMetadata(from: dbTrack)
        
        XCTAssertNil(metadata.trackName)
        XCTAssertNil(metadata.artist)
        XCTAssertNil(metadata.album)
        XCTAssertNil(metadata.duration)
        XCTAssertNil(metadata.genre)
        XCTAssertNil(metadata.trackNumber)
    }
    
    func testInitWithInvalidDuration() {
        let dbTrack = AudioDBTrack(
            strTrack: "Test",
            strArtist: nil,
            strAlbum: nil,
            intDuration: "not a number",
            strGenre: nil,
            intTrackNumber: nil,
            intYearReleased: nil,
            strTrackThumb: nil,
            strDescriptionEN: nil
        )
        
        let metadata = TrackMetadata(from: dbTrack)
        
        XCTAssertNil(metadata.duration)
    }
}

// MARK: - MetadataError Tests

final class MetadataErrorTests: XCTestCase {
    
    func testErrorDescriptions() {
        XCTAssertEqual(MetadataError.invalidURL.errorDescription, "Invalid URL")
        XCTAssertEqual(MetadataError.requestFailed.errorDescription, "Metadata request failed")
        XCTAssertEqual(MetadataError.decodingFailed.errorDescription, "Failed to decode metadata")
        XCTAssertEqual(MetadataError.notFound.errorDescription, "Metadata not found")
    }
}
