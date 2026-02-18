import XCTest
@testable import Wavefront

/// Integration tests for the audio source system
final class AudioSourceIntegrationTests: XCTestCase {
    
    var tempDirectory: URL!
    var manager: AudioSourceManager!
    
    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WavefrontIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        manager = AudioSourceManager()
    }
    
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        manager = nil
    }
    
    // MARK: - Multi-Source Integration Tests
    
    func testMultipleLocalSourcesWithDifferentDirectories() async throws {
        // Setup: Create two separate directories with different music
        let jazzDir = tempDirectory.appendingPathComponent("jazz")
        let rockDir = tempDirectory.appendingPathComponent("rock")
        
        try FileManager.default.createDirectory(at: jazzDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rockDir, withIntermediateDirectories: true)
        
        try Data().write(to: jazzDir.appendingPathComponent("blue_train.mp3"))
        try Data().write(to: jazzDir.appendingPathComponent("so_what.mp3"))
        try Data().write(to: rockDir.appendingPathComponent("smoke_on_water.mp3"))
        
        let jazzSource = LocalAudioSource(sourceId: "jazz", displayName: "Jazz", baseDirectory: jazzDir)
        let rockSource = LocalAudioSource(sourceId: "rock", displayName: "Rock", baseDirectory: rockDir)
        
        await manager.register(jazzSource)
        await manager.register(rockSource)
        
        // Test: Fetch all tracks combines both sources
        let allTracks = await manager.fetchAllTracks()
        XCTAssertEqual(allTracks.count, 3)
        
        // Test: Fetch from specific source
        let jazzTracks = try await manager.fetchTracks(from: "jazz")
        XCTAssertEqual(jazzTracks.count, 2)
        
        let rockTracks = try await manager.fetchTracks(from: "rock")
        XCTAssertEqual(rockTracks.count, 1)
    }
    
    func testSourceAvailabilityChanges() async throws {
        let dir = tempDirectory.appendingPathComponent("available")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let source = LocalAudioSource(sourceId: "test", displayName: "Test", baseDirectory: dir)
        await manager.register(source)
        
        // Initially available
        var available = await manager.availableSources()
        XCTAssertEqual(available.count, 1)
        
        // Remove the directory
        try FileManager.default.removeItem(at: dir)
        
        // Now unavailable
        available = await manager.availableSources()
        XCTAssertEqual(available.count, 0)
        
        // Recreate directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Available again
        available = await manager.availableSources()
        XCTAssertEqual(available.count, 1)
    }
    
    func testTrackPlayabilityAcrossSources() async throws {
        let dir = tempDirectory.appendingPathComponent("music")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let songURL = dir.appendingPathComponent("song.mp3")
        try Data().write(to: songURL)
        
        let source = LocalAudioSource(sourceId: "main", displayName: "Main", baseDirectory: dir)
        await manager.register(source)
        
        let tracks = try await manager.fetchTracks(from: "main")
        XCTAssertEqual(tracks.count, 1)
        
        let track = tracks[0]
        let playableURL = try await manager.getPlayableURL(for: track)
        
        XCTAssertEqual(playableURL, songURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: playableURL.path))
    }
    
    // MARK: - Nested Directory Structure Tests
    
    func testDeepNestedDirectoryStructure() async throws {
        // Create a realistic music library structure
        let artistDir = tempDirectory.appendingPathComponent("Artist Name")
        let album1 = artistDir.appendingPathComponent("Album One")
        let album2 = artistDir.appendingPathComponent("Album Two")
        
        try FileManager.default.createDirectory(at: album1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: album2, withIntermediateDirectories: true)
        
        try Data().write(to: album1.appendingPathComponent("01 Track One.mp3"))
        try Data().write(to: album1.appendingPathComponent("02 Track Two.mp3"))
        try Data().write(to: album2.appendingPathComponent("01 First Song.mp3"))
        
        let source = LocalAudioSource(sourceId: "library", displayName: "Library", baseDirectory: tempDirectory)
        
        let tracks = try await source.fetchTracks()
        XCTAssertEqual(tracks.count, 3)
        
        // Test fetching from specific album
        let album1Tracks = try await source.fetchTracks(at: "Artist Name/Album One")
        XCTAssertEqual(album1Tracks.count, 2)
    }
    
    // MARK: - Mixed File Type Tests
    
    func testMixedContentDirectory() async throws {
        // Create directory with mixed content
        try Data().write(to: tempDirectory.appendingPathComponent("song.mp3"))
        try Data().write(to: tempDirectory.appendingPathComponent("cover.jpg"))
        try Data().write(to: tempDirectory.appendingPathComponent("readme.txt"))
        try Data().write(to: tempDirectory.appendingPathComponent("another.m4a"))
        try Data().write(to: tempDirectory.appendingPathComponent(".hidden.mp3"))  // Hidden file
        
        let source = LocalAudioSource(sourceId: "mixed", displayName: "Mixed", baseDirectory: tempDirectory)
        
        let tracks = try await source.fetchTracks()
        
        // Should only find the audio files (including hidden)
        let audioCount = tracks.count
        XCTAssertGreaterThanOrEqual(audioCount, 2)  // At minimum song.mp3 and another.m4a
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentFetchFromMultipleSources() async throws {
        // Setup multiple sources
        for i in 1...5 {
            let dir = tempDirectory.appendingPathComponent("source\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data().write(to: dir.appendingPathComponent("track\(i).mp3"))
            
            let source = LocalAudioSource(
                sourceId: "source\(i)",
                displayName: "Source \(i)",
                baseDirectory: dir
            )
            await manager.register(source)
        }
        
        // Fetch all tracks concurrently
        let tracks = await manager.fetchAllTracks()
        XCTAssertEqual(tracks.count, 5)
    }
    
    // MARK: - Error Handling Tests
    
    func testGracefulHandlingOfInaccessibleSources() async throws {
        // Create one accessible and one inaccessible source
        let accessibleDir = tempDirectory.appendingPathComponent("accessible")
        try FileManager.default.createDirectory(at: accessibleDir, withIntermediateDirectories: true)
        try Data().write(to: accessibleDir.appendingPathComponent("song.mp3"))
        
        let inaccessibleDir = tempDirectory.appendingPathComponent("inaccessible-\(UUID().uuidString)")
        
        let accessibleSource = LocalAudioSource(
            sourceId: "accessible",
            displayName: "Accessible",
            baseDirectory: accessibleDir
        )
        let inaccessibleSource = LocalAudioSource(
            sourceId: "inaccessible",
            displayName: "Inaccessible",
            baseDirectory: inaccessibleDir
        )
        
        await manager.register(accessibleSource)
        await manager.register(inaccessibleSource)
        
        // Should not throw, should return tracks from accessible source
        let tracks = await manager.fetchAllTracks()
        XCTAssertEqual(tracks.count, 1)
    }
}
