//
//  WalkWorthyApp.swift
//  WalkWorthy
//
//  Created by Nathan Jones on 10/4/25.
//  Updated by Codex on 10/5/25.
//

import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks

@main
struct WalkWorthyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    init() {
        BackgroundTasksManager.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                    BackgroundTasksManager.shared.scheduleNextRefresh()
                    appState.refreshEncouragementDeck()
                    if appState.isCanvasLinked {
                        appState.refreshCanvasSummary()
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationScheduler.shared
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundTasksManager.shared.scheduleNextRefresh()
    }
}
