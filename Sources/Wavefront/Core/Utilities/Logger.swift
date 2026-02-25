import Foundation
import os.log

/**
 * Centralized logging system for Wavefront app.
 *
 * Provides structured logging with different levels and categories
 * for easier debugging and issue tracking.
 *
 * ## Usage
 * ```swift
 * Logger.debug("Loading track", category: .audio)
 * Logger.info("Track loaded: \(track.title)", category: .audio)
 * Logger.warning("Network slow", category: .network)
 * Logger.error("Failed to load", error: error, category: .spotify)
 * ```
 */
public enum Logger {
    
    /// Log categories for filtering
    public enum Category: String {
        case audio = "Audio"
        case spotify = "Spotify"
        case youtube = "YouTube"
        case network = "Network"
        case ui = "UI"
        case library = "Library"
        case metadata = "Metadata"
        case storage = "Storage"
        case general = "General"
        
        var osLog: OSLog {
            OSLog(subsystem: Bundle.main.bundleIdentifier ?? "com.wavefront", category: rawValue)
        }
    }
    
    /// Log levels
    public enum Level: String {
        case debug = "🔍 DEBUG"
        case info = "ℹ️ INFO"
        case warning = "⚠️ WARNING"
        case error = "❌ ERROR"
        case success = "✅ SUCCESS"
    }
    
    /// Enable/disable logging (can be toggled for release builds)
    public static var isEnabled = true
    
    /// Minimum log level to display
    public static var minimumLevel: Level = .debug
    
    /// Store recent logs for debugging UI
    private static var recentLogs: [LogEntry] = []
    private static let maxLogCount = 500
    private static let logQueue = DispatchQueue(label: "com.wavefront.logger", qos: .utility)
    
    /// Log entry structure
    public struct LogEntry: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let level: Level
        public let category: Category
        public let message: String
        public let file: String
        public let function: String
        public let line: Int
        
        public var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
        
        public var shortFile: String {
            URL(fileURLWithPath: file).lastPathComponent
        }
    }
    
    // MARK: - Public Methods
    
    /// Log a debug message
    public static func debug(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .debug, message: message, category: category, file: file, function: function, line: line)
    }
    
    /// Log an info message
    public static func info(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .info, message: message, category: category, file: file, function: function, line: line)
    }
    
    /// Log a warning message
    public static func warning(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .warning, message: message, category: category, file: file, function: function, line: line)
    }
    
    /// Log an error message
    public static func error(
        _ message: String,
        error: Error? = nil,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        var fullMessage = message
        if let error = error {
            fullMessage += " | Error: \(error.localizedDescription)"
        }
        log(level: .error, message: fullMessage, category: category, file: file, function: function, line: line)
    }
    
    /// Log a success message
    public static func success(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(level: .success, message: message, category: category, file: file, function: function, line: line)
    }
    
    /// Get recent logs for debugging UI
    public static func getRecentLogs(category: Category? = nil) -> [LogEntry] {
        logQueue.sync {
            if let category = category {
                return recentLogs.filter { $0.category == category }
            }
            return recentLogs
        }
    }
    
    /// Clear all logs
    public static func clearLogs() {
        logQueue.async {
            recentLogs.removeAll()
        }
    }
    
    // MARK: - Private Methods
    
    private static func log(
        level: Level,
        message: String,
        category: Category,
        file: String,
        function: String,
        line: Int
    ) {
        guard isEnabled else { return }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line
        )
        
        // Store in memory
        logQueue.async {
            recentLogs.append(entry)
            if recentLogs.count > maxLogCount {
                recentLogs.removeFirst(recentLogs.count - maxLogCount)
            }
        }
        
        // Print to console
        let logString = "[\(entry.formattedTimestamp)] \(level.rawValue) [\(category.rawValue)] \(entry.shortFile):\(line) - \(message)"
        print(logString)
        
        // Also log to os_log for system integration
        let osLogType: OSLogType
        switch level {
        case .debug:
            osLogType = .debug
        case .info, .success:
            osLogType = .info
        case .warning:
            osLogType = .default
        case .error:
            osLogType = .error
        }
        
        os_log("%{public}@", log: category.osLog, type: osLogType, message)
    }
}

// MARK: - Convenience Extensions

extension Logger {
    /// Log network request
    public static func logRequest(url: String, method: String = "GET", category: Category = .network) {
        debug("📤 \(method) \(url)", category: category)
    }
    
    /// Log network response
    public static func logResponse(url: String, statusCode: Int, category: Category = .network) {
        if (200...299).contains(statusCode) {
            debug("📥 \(statusCode) \(url)", category: category)
        } else {
            warning("📥 \(statusCode) \(url)", category: category)
        }
    }
    
    /// Log with data dump for debugging
    public static func dump(_ value: Any, label: String, category: Category = .general) {
        var output = ""
        Swift.dump(value, to: &output)
        debug("\(label):\n\(output)", category: category)
    }
}
