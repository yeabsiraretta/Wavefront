import Foundation
#if os(iOS)
import UIKit
import BackgroundTasks
#endif

/// Manages background downloads for the app
/// Allows downloads to continue when the app is backgrounded or suspended
public final class BackgroundDownloadManager: NSObject, @unchecked Sendable {
    
    /// Shared singleton instance
    public static let shared = BackgroundDownloadManager()
    
    /// Background URLSession identifier
    private static let backgroundSessionIdentifier = "com.wavefront.backgroundDownload"
    
    /// Background task identifier for processing
    public static let backgroundTaskIdentifier = "com.wavefront.downloadProcessing"
    
    /// Background URLSession for downloads
    private lazy var backgroundSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.timeoutIntervalForResource = 60 * 60 // 1 hour max
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    /// Active download tasks mapped by task identifier
    private var activeDownloads: [Int: DownloadInfo] = [:]
    
    /// Lock for thread-safe access to activeDownloads
    private let lock = NSLock()
    
    /// Completion handler for background session events
    public var backgroundCompletionHandler: (() -> Void)?
    
    /// Download progress callbacks
    private var progressHandlers: [Int: (Double) -> Void] = [:]
    
    /// Download completion callbacks
    private var completionHandlers: [Int: (Result<URL, Error>) -> Void] = [:]
    
    /// Download directory
    private lazy var downloadDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let musicDir = docs.appendingPathComponent("Music")
        try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        return musicDir
    }()
    
    private override init() {
        super.init()
        Logger.info("BackgroundDownloadManager initialized", category: .network)
    }
    
    /// Info about an active download
    struct DownloadInfo {
        let url: URL
        let destinationFilename: String
        let startTime: Date
        var bytesReceived: Int64 = 0
        var totalBytes: Int64 = 0
    }
    
    // MARK: - Public API
    
    /// Register background task handlers (call from AppDelegate)
    #if os(iOS)
    public func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.backgroundTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task as! BGProcessingTask)
        }
        Logger.info("Registered background task handler", category: .network)
    }
    #endif
    
    /// Start a background download
    /// - Parameters:
    ///   - url: URL to download from
    ///   - filename: Destination filename
    ///   - progressHandler: Optional progress callback (0.0 to 1.0)
    ///   - completion: Completion callback with downloaded file URL or error
    /// - Returns: Download task identifier for tracking
    @discardableResult
    public func startDownload(
        from url: URL,
        filename: String,
        progressHandler: ((Double) -> Void)? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> Int {
        let task = backgroundSession.downloadTask(with: url)
        let taskId = task.taskIdentifier
        
        lock.lock()
        activeDownloads[taskId] = DownloadInfo(
            url: url,
            destinationFilename: filename,
            startTime: Date()
        )
        if let handler = progressHandler {
            progressHandlers[taskId] = handler
        }
        completionHandlers[taskId] = completion
        lock.unlock()
        
        Logger.info("Starting background download: \(filename)", category: .network)
        task.resume()
        
        return taskId
    }
    
    /// Cancel a download by task identifier
    public func cancelDownload(taskId: Int) {
        backgroundSession.getTasksWithCompletionHandler { [weak self] _, _, downloadTasks in
            if let task = downloadTasks.first(where: { $0.taskIdentifier == taskId }) {
                task.cancel()
                Logger.info("Cancelled download task: \(taskId)", category: .network)
            }
            self?.cleanupTask(taskId)
        }
    }
    
    /// Get download progress for a task
    public func getProgress(taskId: Int) -> Double {
        lock.lock()
        defer { lock.unlock() }
        
        guard let info = activeDownloads[taskId], info.totalBytes > 0 else {
            return 0
        }
        return Double(info.bytesReceived) / Double(info.totalBytes)
    }
    
    /// Handle background session events (call from AppDelegate)
    public func handleEventsForBackgroundURLSession(
        identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        if identifier == Self.backgroundSessionIdentifier {
            backgroundCompletionHandler = completionHandler
            Logger.info("Handling background session events", category: .network)
            // Accessing backgroundSession will trigger reconnection
            _ = backgroundSession
        }
    }
    
    // MARK: - Private
    
    private func cleanupTask(_ taskId: Int) {
        lock.lock()
        activeDownloads.removeValue(forKey: taskId)
        progressHandlers.removeValue(forKey: taskId)
        completionHandlers.removeValue(forKey: taskId)
        lock.unlock()
    }
    
    #if os(iOS)
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        Logger.info("Handling background processing task", category: .network)
        
        task.expirationHandler = {
            Logger.warning("Background task expired", category: .network)
            task.setTaskCompleted(success: false)
        }
        
        // Check if there are pending downloads
        backgroundSession.getTasksWithCompletionHandler { _, _, downloadTasks in
            if downloadTasks.isEmpty {
                Logger.info("No pending downloads, completing background task", category: .network)
                task.setTaskCompleted(success: true)
            } else {
                Logger.info("Processing \(downloadTasks.count) pending downloads", category: .network)
                // Task will complete when downloads finish via delegate
            }
        }
    }
    
    /// Schedule background processing task
    public func scheduleBackgroundProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        
        do {
            try BGTaskScheduler.shared.submit(request)
            Logger.info("Scheduled background processing task", category: .network)
        } catch {
            Logger.error("Failed to schedule background task", error: error, category: .network)
        }
    }
    #endif
    
    /// Send local notification when download completes
    #if os(iOS)
    private func sendDownloadCompleteNotification(filename: String) {
        let content = UNMutableNotificationContent()
        content.title = "Download Complete"
        content.body = "\(filename) has been downloaded"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.error("Failed to send notification", error: error, category: .network)
            }
        }
    }
    #endif
}

// MARK: - URLSessionDelegate

extension BackgroundDownloadManager: URLSessionDelegate {
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Logger.info("Background session finished all events", category: .network)
        
        DispatchQueue.main.async { [weak self] in
            self?.backgroundCompletionHandler?()
            self?.backgroundCompletionHandler = nil
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundDownloadManager: URLSessionDownloadDelegate {
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier
        
        lock.lock()
        let info = activeDownloads[taskId]
        let completion = completionHandlers[taskId]
        lock.unlock()
        
        guard let downloadInfo = info else {
            Logger.warning("No download info for completed task: \(taskId)", category: .network)
            return
        }
        
        // Move file to final destination
        let destinationURL = downloadDirectory.appendingPathComponent(downloadInfo.destinationFilename)
        
        do {
            // Remove existing file if present
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            let elapsed = Date().timeIntervalSince(downloadInfo.startTime)
            Logger.success("Download complete: \(downloadInfo.destinationFilename) in \(String(format: "%.1f", elapsed))s", category: .network)
            
            #if os(iOS)
            // Send notification if app is backgrounded
            if UIApplication.shared.applicationState != .active {
                sendDownloadCompleteNotification(filename: downloadInfo.destinationFilename)
            }
            #endif
            
            completion?(.success(destinationURL))
        } catch {
            Logger.error("Failed to move downloaded file", error: error, category: .network)
            completion?(.failure(error))
        }
        
        cleanupTask(taskId)
    }
    
    public func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        
        lock.lock()
        activeDownloads[taskId]?.bytesReceived = totalBytesWritten
        activeDownloads[taskId]?.totalBytes = totalBytesExpectedToWrite
        let progressHandler = progressHandlers[taskId]
        lock.unlock()
        
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            progressHandler?(progress)
        }
    }
    
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error else { return }
        
        let taskId = task.taskIdentifier
        
        lock.lock()
        let completion = completionHandlers[taskId]
        lock.unlock()
        
        Logger.error("Download failed", error: error, category: .network)
        completion?(.failure(error))
        
        cleanupTask(taskId)
    }
}

#if os(iOS)
import UserNotifications
#endif
