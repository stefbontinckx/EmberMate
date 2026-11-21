//
//  NotificationAdapter.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/16/23.
//

import Foundation
import SwiftUI
import Combine
import UserNotifications

func postNotification(id: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
}

// Without a delegate, macOS drops banners while EmberBar itself is active,
// e.g. while the menu bar window is open.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}

class NotificationAdapter {
    private var appState: AppState
    private var emberMug: EmberMug

    private var cancellables: Set<AnyCancellable> = []

    // Target temperature we already announced for the current fill.
    private var lastNotifiedTemp: Double?
    private var emptySince: Date?
    private var wasLowBattery = false
    private var notifiedCharged = false

    init(appState: AppState, emberMug: EmberMug) {
        self.appState = appState
        self.emberMug = emberMug

        Publishers.CombineLatest(
            emberMug.$liquidState.dropFirst(),
            emberMug.$targetTemp.dropFirst()
        )
        .sink { [weak self] state, target in
            guard let self else { return }
            if state == .empty {
                if self.emptySince == nil { self.emptySince = Date() }
                return
            }
            // A real refill (empty for over a minute, not a lifted mug) is announced again.
            if let emptySince = self.emptySince {
                if Date().timeIntervalSince(emptySince) >= 60 {
                    self.lastNotifiedTemp = nil
                }
                self.emptySince = nil
            }
            switch state {
            case .stableTemperature where target >= EmberMug.minTemp && target != self.lastNotifiedTemp:
                self.lastNotifiedTemp = target
                self.notifyTemperatureReached(target)
            default:
                break
            }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            emberMug.$batteryLevel.dropFirst(),
            emberMug.$isCharging
        )
        .sink { [weak self] level, charging in
            self?.batteryChanged(level: level, charging: charging)
        }
        .store(in: &cancellables)
    }

    private func batteryChanged(level: Int, charging: Bool) {
        let threshold = appState.notifyAtBatteryPercentage
        if threshold != .off && level <= threshold.rawValue {
            if !wasLowBattery && !charging {
                notifyLowBattery(level)
            }
            wasLowBattery = true
        } else {
            wasLowBattery = false
        }

        if charging && level >= 100 {
            if !notifiedCharged && appState.notifyWhenCharged {
                postNotification(
                    id: "charged",
                    title: String(localized: "Mug fully charged"),
                    body: String(localized: "\(emberMug.displayName) is at 100%.")
                )
            }
            notifiedCharged = true
        } else if !charging {
            notifiedCharged = false
        }
    }

    private func notifyTemperatureReached(_ target: Double) {
        guard appState.notifyOnTemperatureReached else { return }
        let temperature = getFormattedTemperature(target, unit: emberMug.temperatureUnit)
        postNotification(
            id: "tempReached",
            title: String(localized: "Target temperature reached"),
            body: String(localized: "Your drink is now \(temperature).")
        )
    }

    private func notifyLowBattery(_ level: Int) {
        let percentage = getFormattedBatteryLevel(level)
        postNotification(
            id: "lowBattery",
            title: String(localized: "Mug battery low"),
            body: String(localized: "Battery at \(percentage). Put the mug on its coaster to keep it warm.")
        )
    }
}
