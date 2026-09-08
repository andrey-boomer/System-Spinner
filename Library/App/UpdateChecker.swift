//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    static let repositoryURL = URL(string: "https://github.com/andrey-lysikov/System-Spinner")!
    static let latestReleaseURL = URL(string: "https://github.com/andrey-lysikov/System-Spinner/releases/latest")!

    private static let apiURL = URL(string: "https://api.github.com/repos/andrey-lysikov/System-Spinner/releases/latest")!
    private static let backgroundDelay: TimeInterval = 600

    private struct Release: Decodable {
        var tagName: String
    }

    private let preferences = Preferences.shared
    private let notifications = NotificationService.shared
    private var isChecking = false
    private var pendingCheck: DispatchWorkItem?
    private var runningTask: URLSessionDataTask?

    private init() {}

    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    func check(force: Bool = false) {
        guard !installedVersion.isEmpty else { return }

        if force {
            cancelRunningCheck()
        } else {
            guard !isChecking else { return }
            if let last = preferences.lastVersionCheck, Calendar.current.isDateInToday(last) { return }
        }

        isChecking = true
        let installed = installedVersion

        let work = DispatchWorkItem { [self] in
            let task = URLSession.shared.dataTask(with: Self.apiURL) { data, _, _ in
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let release = data.flatMap { try? decoder.decode(Release.self, from: $0) }

                Task { @MainActor in
                    Self.shared.finish(release: release, installed: installed, force: force)
                }
            }
            runningTask = task
            task.resume()
        }

        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: force ? .now() : .now() + Self.backgroundDelay, execute: work)
    }

    private func cancelRunningCheck() {
        pendingCheck?.cancel()
        pendingCheck = nil
        runningTask?.cancel()
        runningTask = nil
        isChecking = false
    }

    private func finish(release: Release?, installed: String, force: Bool) {
        isChecking = false
        pendingCheck = nil
        runningTask = nil
        guard let release else { return }

        let latest = Self.versionNumber(release.tagName)
        let current = Self.versionNumber(installed)

        if latest > 0, current > 0, latest > current {
            notifications.send(title: localizedString("System Spinner update"),
                               body: localizedString("New version \(release.tagName) is available. Would you like download to update?"),
                               action: .download)
        } else if force {
            notifications.send(title: localizedString("System Spinner update"),
                               body: localizedString("You version \(installed) is actual version."))
        }

        preferences.lastVersionCheck = Date()
    }

    nonisolated static func versionNumber(_ value: String) -> Int {
        let scale = [1_000_000, 1_000, 1]
        let components = value.split(whereSeparator: { !$0.isNumber }).prefix(scale.count)
        guard !components.isEmpty else { return 0 }

        return zip(components, scale).reduce(0) { total, pair in
            total + (Int(pair.0) ?? 0) * pair.1
        }
    }
}
