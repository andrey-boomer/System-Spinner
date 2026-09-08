//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

@preconcurrency import ApplicationServices
import Cocoa
@preconcurrency import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateOtherInstances()

        UNUserNotificationCenter.current().delegate = self
        statusItemController.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaKeyMonitor.shared.stop()
        statusItemController.stop()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        where app.processIdentifier != NSRunningApplication.current.processIdentifier {
            app.terminate()
        }
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch NotificationAction(rawValue: response.actionIdentifier) {
        case .allowPrivileges:
            AccessibilityPermission.request()
        case .download:
            NSWorkspace.shared.open(UpdateChecker.latestReleaseURL)
        case nil:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum AccessibilityPermission {
    static var isTrusted: Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func check() -> Bool {
        guard isTrusted else {
            NotificationService.shared.send(
                title: localizedString("System Spinner need special privileges"),
                body: localizedString("For complite work you need to allow System Spinner to use special privileges for keydoard mapping."),
                action: .allowPrivileges
            )
            return false
        }
        return true
    }

    static func request() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
    }
}

enum NotificationAction: String {
    case allowPrivileges = "action.allow"
    case download = "action.download"

    var title: String {
        switch self {
        case .allowPrivileges: return localizedString("Allow")
        case .download: return localizedString("Download")
        }
    }
}

final class NotificationService: Sendable {
    static let shared = NotificationService()

    private static let categoryIdentifier = "ACTION"

    private init() {}

    func send(title: String, body: String = "", action: NotificationAction? = nil) {
        let center = UNUserNotificationCenter.current()

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            if let action {
                let button = UNNotificationAction(identifier: action.rawValue, title: action.title, options: [])
                let category = UNNotificationCategory(identifier: Self.categoryIdentifier,
                                                      actions: [button],
                                                      intentIdentifiers: [],
                                                      hiddenPreviewsBodyPlaceholder: "",
                                                      options: .customDismissAction)
                content.categoryIdentifier = Self.categoryIdentifier
                center.setNotificationCategories([category])
            }

            center.removeAllPendingNotificationRequests()
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
