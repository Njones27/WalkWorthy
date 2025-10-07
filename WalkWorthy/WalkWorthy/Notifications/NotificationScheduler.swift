////  NotificationScheduler.swift
//  WalkWorthy
//
//  Handles opting into and scheduling local notifications.
//

import Foundation
import UserNotifications

final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationScheduler()

    private let center = UNUserNotificationCenter.current()
    private let authorizationKey = "walkworthy.notifications.authorized"

    private override init() {
        super.init()
    }

    @MainActor
    func requestAuthorizationIfNeeded() async {
        let defaults = UserDefaults.standard
        center.delegate = self

        do {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                defaults.set(true, forKey: authorizationKey)
                return
            case .notDetermined:
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                defaults.set(granted, forKey: authorizationKey)
            default:
                defaults.set(false, forKey: authorizationKey)
            }
        } catch {
            defaults.set(false, forKey: authorizationKey)
            print("[NotificationScheduler] Authorization error: \(error)")
        }
    }

    func scheduleTestNotification(in seconds: TimeInterval = 10) {
        Task {
            if !(await isAuthorized) {
                await requestAuthorizationIfNeeded()
            }
            guard await isAuthorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "WalkWorthy"
            content.body = "This is your test encouragement notification."
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.encouragement.rawValue

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                print("[NotificationScheduler] Failed to schedule test notification: \(error)")
            }
        }
    }

    func scheduleEncouragementNotification(_ payload: EncouragementPayload?) {
        Task {
            guard await isAuthorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "Stay encouraged"
            content.body = payload?.encouragement ?? "Tap to see today’s encouragement."
            content.sound = .default
            if let payload {
                content.userInfo = [
                    "id": payload.id,
                    "ref": payload.ref,
                    "translation": payload.translation ?? Translation.esv.rawValue
                ]
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                print("[NotificationScheduler] Failed to schedule encouragement notification: \(error)")
            }
        }
    }

    private var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
    }

    enum NotificationCategory: String {
        case encouragement = "walkworthy.encouragement"
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
