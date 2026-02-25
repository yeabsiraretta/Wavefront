import Foundation
import SwiftUI
#if os(iOS)
import UIKit
import AVFoundation
import UserNotifications
import BackgroundTasks

/// Main AppDelegate for Wavefront
/// Handles background downloads, audio session, and app lifecycle
public class WavefrontAppDelegate: NSObject, UIApplicationDelegate {
    
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        
        // Configure audio session for background playback
        configureAudioSession()
        
        // Register background task handlers
        registerBackgroundTasks()
        
        // Request notification permissions
        requestNotificationPermissions()
        
        Logger.info("Wavefront app launched", category: .general)
        
        return true
    }
    
    public func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        Logger.info("Handling background URL session: \(identifier)", category: .network)
        BackgroundDownloadManager.shared.handleEventsForBackgroundURLSession(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
    
    public func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.info("App entered background", category: .general)
        // Schedule background processing if there are active downloads
        BackgroundDownloadManager.shared.scheduleBackgroundProcessing()
    }
    
    public func applicationWillTerminate(_ application: UIApplication) {
        Logger.info("App will terminate", category: .general)
    }
    
    // MARK: - Private Configuration
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
            Logger.success("Audio session configured", category: .audio)
        } catch {
            Logger.error("Failed to configure audio session", error: error, category: .audio)
        }
    }
    
    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundDownloadManager.backgroundTaskIdentifier,
            using: nil
        ) { task in
            self.handleBackgroundTask(task as! BGProcessingTask)
        }
        Logger.info("Background tasks registered", category: .network)
    }
    
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        Logger.info("Handling background task", category: .network)
        
        task.expirationHandler = {
            Logger.warning("Background task expired", category: .network)
            task.setTaskCompleted(success: false)
        }
        
        // The BackgroundDownloadManager will handle active downloads
        // Complete the task when done
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            task.setTaskCompleted(success: true)
        }
    }
    
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, error in
            if granted {
                Logger.info("Notification permissions granted", category: .general)
            } else if let error = error {
                Logger.error("Notification permission error", error: error, category: .general)
            }
        }
    }
}
#endif
