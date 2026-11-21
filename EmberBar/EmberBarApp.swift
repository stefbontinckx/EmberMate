//
//  EmberBarApp.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/4/23.
//

import SwiftUI
import UserNotifications

@main
struct EmberBarApp: App {
    @ObservedObject private var emberMug: EmberMug
    @ObservedObject private var bluetoothManager: BluetoothManager
    @ObservedObject private var appState: AppState

    @ObservedObject private var autoOff: AutoOffController
    @ObservedObject private var drinkTracker: DrinkTracker
    @AppStorage("menuBarShowsTimeToTarget") private var menuBarShowsTimeToTarget = false

    private var notificationAdapter: NotificationAdapter

    init() {
        let mug = EmberMug()
        self.emberMug = mug
        bluetoothManager = BluetoothManager(emberMug: mug)

        let state = AppState()
        self.appState = state

        self.notificationAdapter = NotificationAdapter(appState: state, emberMug: mug)
        self.autoOff = AutoOffController(appState: state, emberMug: mug)
        self.drinkTracker = DrinkTracker(emberMug: mug)
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        MenuBarExtra() {
            AppView()
                .environmentObject(emberMug)
                .environmentObject(appState)
                .environmentObject(bluetoothManager)
                .environmentObject(autoOff)
                .environmentObject(drinkTracker)
        } label: {
            HStack {
                menuBarImage
                
                if (appState.countdown != nil) {
                    Text(formatCountdown(appState.countdown!))
                } else if isAtTemperature {
                    // The check mark in the icon says it all.
                    EmptyView()
                } else if (bluetoothManager.state == .connected && emberMug.liquidState != .empty) {
                    // While heating or cooling, optionally show the time left instead;
                    // otherwise (or without an estimate yet) the temperature.
                    if menuBarShowsTimeToTarget, let minutes = drinkTracker.minutesToTarget {
                        Text("~\(minutes) min")
                    } else {
                        Text(getFormattedTemperature(emberMug.currentTemp, unit: emberMug.temperatureUnit))
                    }
                } else if (bluetoothManager.state == .connected && emberMug.liquidState == .empty && emberMug.batteryLevel != 100 && emberMug.isCharging) {
                    Text(getFormattedBatteryLevel(emberMug.batteryLevel))
                }
            }
        }.menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .frame(width: 460, height: 560)
                .environmentObject(emberMug)
                .environmentObject(appState)
                .environmentObject(bluetoothManager)
                .environmentObject(autoOff)
                .environmentObject(drinkTracker)
            
        }
    }

    // Clock while a timer runs, a check once the drink is at temperature,
    // otherwise a mug that fills with the liquid level.
    @ViewBuilder
    private var menuBarImage: some View {
        let connected = bluetoothManager.state == .connected
        if appState.countdown != nil {
            Image(systemName: "clock.fill")
        } else if !connected || emberMug.liquidState == .empty {
            Image(nsImage: MenuBarIcon.mug(fill: 0))
        } else {
            // Unknown level: show the mug as full.
            Image(nsImage: MenuBarIcon.mug(fill: emberMug.estimatedFillFraction ?? 1, check: isAtTemperature))
        }
    }

    private var isAtTemperature: Bool {
        bluetoothManager.state == .connected
            && emberMug.liquidState == .stableTemperature
            && !emberMug.isHeatingOff
    }

    func formatCountdown(_ countdown: Int) -> String {
        let roundedMinutes = countdown.dividedReportingOverflow(by: 60)
        let minutes = roundedMinutes.partialValue
        
        if (minutes == 0) {
            return ">1min"
        }
        return "\(minutes)min"
    }
}

private struct OpenSettingsBackportKey: EnvironmentKey {
    static let defaultValue: () -> Void = {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension EnvironmentValues {
    var openSettings_backport: () -> Void {
        get {
            if #available(macOS 14.0, *) {
                return { [openSettings] in
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                return self[OpenSettingsBackportKey.self]
            }
        }
        set { self[OpenSettingsBackportKey.self] = newValue }
    }
}
