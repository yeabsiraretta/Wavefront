import XCTest
@testable import Wavefront

final class LoggerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        Logger.isEnabled = true
        Logger.clearLogs()
    }
    
    override func tearDown() {
        Logger.clearLogs()
        super.tearDown()
    }
    
    // MARK: - Category Tests
    
    func testAllCategoriesExist() {
        let categories: [Logger.Category] = [
            .audio, .spotify, .youtube, .network,
            .ui, .library, .metadata, .storage, .general
        ]
        XCTAssertEqual(categories.count, 9)
    }
    
    func testCategoryRawValues() {
        XCTAssertEqual(Logger.Category.audio.rawValue, "Audio")
        XCTAssertEqual(Logger.Category.spotify.rawValue, "Spotify")
        XCTAssertEqual(Logger.Category.youtube.rawValue, "YouTube")
        XCTAssertEqual(Logger.Category.network.rawValue, "Network")
        XCTAssertEqual(Logger.Category.storage.rawValue, "Storage")
    }
    
    // MARK: - Level Tests
    
    func testAllLevelsExist() {
        let levels: [Logger.Level] = [
            .debug, .info, .warning, .error, .success
        ]
        XCTAssertEqual(levels.count, 5)
    }
    
    func testLevelRawValues() {
        XCTAssertTrue(Logger.Level.debug.rawValue.contains("DEBUG"))
        XCTAssertTrue(Logger.Level.info.rawValue.contains("INFO"))
        XCTAssertTrue(Logger.Level.warning.rawValue.contains("WARNING"))
        XCTAssertTrue(Logger.Level.error.rawValue.contains("ERROR"))
        XCTAssertTrue(Logger.Level.success.rawValue.contains("SUCCESS"))
    }
    
    // MARK: - Logging Tests
    
    func testDebugLogging() {
        Logger.debug("Test debug message", category: .general)
        
        let logs = Logger.getRecentLogs()
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        
        if let lastLog = logs.last {
            XCTAssertEqual(lastLog.level, .debug)
            XCTAssertEqual(lastLog.category, .general)
            XCTAssertTrue(lastLog.message.contains("Test debug message"))
        }
    }
    
    func testInfoLogging() {
        Logger.info("Test info message", category: .audio)
        
        let logs = Logger.getRecentLogs(category: .audio)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        
        if let lastLog = logs.last {
            XCTAssertEqual(lastLog.level, .info)
            XCTAssertEqual(lastLog.category, .audio)
        }
    }
    
    func testWarningLogging() {
        Logger.warning("Test warning", category: .network)
        
        let logs = Logger.getRecentLogs(category: .network)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
    }
    
    func testErrorLogging() {
        let testError = NSError(domain: "test", code: 123, userInfo: nil)
        Logger.error("Test error", error: testError, category: .spotify)
        
        let logs = Logger.getRecentLogs(category: .spotify)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        
        if let lastLog = logs.last {
            XCTAssertEqual(lastLog.level, .error)
            XCTAssertTrue(lastLog.message.contains("Test error"))
        }
    }
    
    func testSuccessLogging() {
        Logger.success("Operation completed", category: .storage)
        
        let logs = Logger.getRecentLogs(category: .storage)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        
        if let lastLog = logs.last {
            XCTAssertEqual(lastLog.level, .success)
        }
    }
    
    // MARK: - Log Entry Tests
    
    func testLogEntryFormattedTimestamp() {
        Logger.debug("Test", category: .general)
        
        let logs = Logger.getRecentLogs()
        if let lastLog = logs.last {
            // Timestamp should be in HH:mm:ss.SSS format
            XCTAssertTrue(lastLog.formattedTimestamp.contains(":"))
        }
    }
    
    func testLogEntryShortFile() {
        Logger.debug("Test", category: .general)
        
        let logs = Logger.getRecentLogs()
        if let lastLog = logs.last {
            // Short file should just be the filename, not full path
            XCTAssertFalse(lastLog.shortFile.contains("/"))
            XCTAssertTrue(lastLog.shortFile.hasSuffix(".swift"))
        }
    }
    
    // MARK: - Filtering Tests
    
    func testGetRecentLogsByCategory() {
        Logger.debug("Audio log", category: .audio)
        Logger.debug("Network log", category: .network)
        Logger.debug("Audio log 2", category: .audio)
        
        let audioLogs = Logger.getRecentLogs(category: .audio)
        let networkLogs = Logger.getRecentLogs(category: .network)
        
        XCTAssertGreaterThanOrEqual(audioLogs.count, 2)
        XCTAssertGreaterThanOrEqual(networkLogs.count, 1)
    }
    
    func testClearLogs() {
        Logger.debug("Test log", category: .general)
        XCTAssertGreaterThan(Logger.getRecentLogs().count, 0)
        
        Logger.clearLogs()
        
        // Give time for async clear
        let expectation = XCTestExpectation(description: "Logs cleared")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(Logger.getRecentLogs().count, 0)
    }
    
    // MARK: - Enable/Disable Tests
    
    func testDisabledLogging() {
        Logger.clearLogs()
        
        // Wait for clear
        let clearExpectation = XCTestExpectation(description: "Clear")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            clearExpectation.fulfill()
        }
        wait(for: [clearExpectation], timeout: 1.0)
        
        Logger.isEnabled = false
        Logger.debug("Should not log", category: .general)
        
        // Wait for potential log
        let logExpectation = XCTestExpectation(description: "Log")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            logExpectation.fulfill()
        }
        wait(for: [logExpectation], timeout: 1.0)
        
        XCTAssertEqual(Logger.getRecentLogs().count, 0)
        
        Logger.isEnabled = true
    }
    
    // MARK: - Convenience Method Tests
    
    func testLogRequest() {
        Logger.logRequest(url: "https://example.com/api", method: "POST", category: .network)
        
        let logs = Logger.getRecentLogs(category: .network)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        
        if let lastLog = logs.last {
            XCTAssertTrue(lastLog.message.contains("POST"))
            XCTAssertTrue(lastLog.message.contains("example.com"))
        }
    }
    
    func testLogResponse() {
        Logger.logResponse(url: "https://example.com/api", statusCode: 200, category: .network)
        
        let logs = Logger.getRecentLogs(category: .network)
        XCTAssertGreaterThanOrEqual(logs.count, 1)
        
        if let lastLog = logs.last {
            XCTAssertTrue(lastLog.message.contains("200"))
        }
    }
}
