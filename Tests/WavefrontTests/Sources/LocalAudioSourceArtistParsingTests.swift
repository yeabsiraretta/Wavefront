import XCTest
@testable import Wavefront

final class LocalAudioSourceArtistParsingTests: XCTestCase {
    
    var tempDirectory: URL!
    var source: LocalAudioSource!
    
    override func setUp() async throws {
        try await super.setUp()
        
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtistParsingTests-\(UUID().uuidString)")
        
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        source = LocalAudioSource(
            sourceId: "test",
            displayName: "Test",
            baseDirectory: tempDirectory
        )
    }
    
    override func tearDown() async throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }
    
    // MARK: - Artist Parsing Tests
    
    func testParseArtistFromTitleWithDash() async throws {
        // Create a file with "Artist - Track" naming
        let filename = "Daft Punk - Get Lucky.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        // Create empty file
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        XCTAssertEqual(track.artist, "Daft Punk")
        XCTAssertEqual(track.title, "Get Lucky")
    }
    
    func testParseArtistFromTitleWithEnDash() async throws {
        // Create a file with en-dash separator
        let filename = "The Beatles – Hey Jude.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        XCTAssertEqual(track.artist, "The Beatles")
        XCTAssertEqual(track.title, "Hey Jude")
    }
    
    func testParseArtistFromTitleWithEmDash() async throws {
        // Create a file with em-dash separator
        let filename = "Queen — Bohemian Rhapsody.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        XCTAssertEqual(track.artist, "Queen")
        XCTAssertEqual(track.title, "Bohemian Rhapsody")
    }
    
    func testParseArtistFromTitleWithUnderscore() async throws {
        // Create a file with underscore separator
        let filename = "Pink Floyd _ Wish You Were Here.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        XCTAssertEqual(track.artist, "Pink Floyd")
        XCTAssertEqual(track.title, "Wish You Were Here")
    }
    
    func testNoArtistParsingWithoutSeparator() async throws {
        // Create a file without separator
        let filename = "SongWithoutArtist.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        XCTAssertNil(track.artist)
        XCTAssertEqual(track.title, "SongWithoutArtist")
    }
    
    func testArtistParsingWithSpacesAroundSeparator() async throws {
        // Create file with extra spaces
        let filename = "Artist Name   -   Song Title.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        // Should trim whitespace
        XCTAssertEqual(track.artist, "Artist Name")
        XCTAssertEqual(track.title, "Song Title")
    }
    
    func testMultipleSeparatorsUsesFirst() async throws {
        // Create file with multiple dashes - should use first separator
        let filename = "Artist - Song - Part 2.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        XCTAssertEqual(track.artist, "Artist")
        // Title should include the rest including the second dash
        XCTAssertEqual(track.title, "Song - Part 2")
    }
    
    func testEmptyPartsNotParsed() async throws {
        // Create file with separator at start (empty artist)
        let filename = " - JustTitle.mp3"
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        FileManager.default.createFile(atPath: fileURL.path, contents: Data(), attributes: nil)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        // Should not parse because artist would be empty
        XCTAssertNil(track.artist)
    }
}
