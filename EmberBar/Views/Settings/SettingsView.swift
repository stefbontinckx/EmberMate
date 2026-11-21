//
//  SettingsView.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/10/23.
//

import Foundation
import SwiftUI
import AppKit
import LaunchAtLogin
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedSettingsTab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            MugSettingsView()
                .tabItem { Label("Mug", systemImage: "mug") }
                .tag("mug")
            PresetsSettingsView()
                .tabItem { Label("Presets", systemImage: "slider.horizontal.3") }
                .tag("presets")
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag("about")
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var drinkTracker: DrinkTracker
    @AppStorage(DrinkTracker.trackingKey) private var trackDrinking = true
    @AppStorage("menuBarShowsTimeToTarget") private var menuBarShowsTimeToTarget = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Picker("Stop heating after", selection: appState.$autoOffMinutes) {
                    ForEach(AutoOffController.choices, id: \.self) { minutes in
                        if minutes == 0 {
                            Text("Never").tag(0)
                        } else {
                            Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide)))
                                .tag(minutes)
                        }
                    }
                }
            } header: {
                Text("Heating")
            } footer: {
                Text("Counts from the moment you fill the mug. Turn heating back on with the power button or a preset.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if appState.notificationsDisabled {
                    LabeledContent {
                        Button("Open System Settings") {
                            openURL(.notificationSettings)
                        }
                    } label: {
                        Label("Notifications are turned off", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Toggle("When the target temperature is reached", isOn: appState.$notifyOnTemperatureReached)

                Picker("When the battery drops to", selection: appState.$notifyAtBatteryPercentage) {
                    ForEach(AppState.LowBatteryLevel.allCases, id: \.rawValue) { level in
                        Text(level.description).tag(level)
                    }
                }

                Toggle("When the mug is fully charged", isOn: appState.$notifyWhenCharged)
            } header: {
                Text("Notifications")
            }
            .disabled(appState.notificationsDisabled)

            Section {
                Toggle("Keep track of what I drink", isOn: $trackDrinking)
                if trackDrinking {
                    LabeledContent("Today") {
                        HStack {
                            (Text("\(drinkTracker.cupsToday) cups") + Text(verbatim: " · ") + Text("about \(drinkTracker.millilitersToday) ml"))
                                .monospacedDigit()
                            Button("Reset") { drinkTracker.resetToday() }
                        }
                    }
                }
            } header: {
                Text("Drinking")
            } footer: {
                Text("A cup counts when the mug goes from filled to empty. Amounts are estimates and stay on this Mac.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Menu bar shows", selection: $menuBarShowsTimeToTarget) {
                    Text("Current temperature").tag(false)
                    Text("Time until ready").tag(true)
                }
                LaunchAtLogin.Toggle { Text("Open at login") }
            } header: {
                Text("App")
            } footer: {
                Text("Time until ready shows while the drink heats up or cools down; otherwise the temperature is shown.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await appState.updateNotificationsDisabled()
        }
    }
}

// MARK: - Mug

struct MugSettingsView: View {
    @EnvironmentObject private var emberMug: EmberMug
    @EnvironmentObject private var bluetoothManager: BluetoothManager

    @State private var nameDraft = ""
    @AppStorage(EmberMug.modelOverrideKey) private var modelOverride = ""

    private var isConnected: Bool { bluetoothManager.state == .connected }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: isConnected ? "mug.fill" : "mug")
                        .font(.system(size: 28))
                        .foregroundStyle(isConnected ? Color.accentColor : .secondary)
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        if isConnected {
                            Text(emberMug.displayName).font(.headline)
                            BatteryView(
                                display: .both,
                                batteryLevel: emberMug.batteryLevel,
                                isCharging: emberMug.isCharging
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            Text("No mug connected").font(.headline)
                            Text("Open EmberBar from the menu bar to connect.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if isConnected {
                        Button("Disconnect") {
                            bluetoothManager.disconnect()
                        }
                    }
                }
            }

            if isConnected && emberMug.canWrite == false {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("This mug doesn't accept changes")
                                .font(.headline)
                            Text("A mug that was reset only accepts changes after it has been set up again in the Ember app. Until then EmberBar can show everything but can't change the temperature, unit, name or light.")
                            Text("1. Open the Ember app on your phone and add the mug.\n2. Once it shows up there, turn off Bluetooth on your phone (or forget the mug there) so it doesn't take over the connection.\n3. Disconnect here and connect the mug again.")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Picker("Temperature unit", selection: Binding(
                    get: { emberMug.temperatureUnit },
                    set: { emberMug.setTemperatureUnit($0) }
                )) {
                    Text("Celsius (℃)").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit (℉)").tag(TemperatureUnit.fahrenheit)
                }

                if isConnected {
                    LabeledContent("Name") {
                        HStack {
                            TextField("Name", text: $nameDraft, prompt: Text(verbatim: emberMug.peripheral?.name ?? "Ember"))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .onSubmit(saveName)
                            Button("Save", action: saveName)
                                .disabled(!canSaveName)
                        }
                    }

                }
            } header: {
                Text("Mug")
            } footer: {
                if isConnected && !nameDraft.isEmpty && !EmberMug.isValidName(nameDraft) {
                    Text("Use up to 16 letters, digits, spaces or simple punctuation.")
                        .foregroundStyle(.red)
                }
            }

            if isConnected, emberMug.ledColor != nil {
                Section {
                    LEDColorPicker()
                } header: {
                    Text("Light")
                } footer: {
                    Text("Changes show on the mug right away.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Model", selection: $modelOverride) {
                    if let model = emberMug.model {
                        Text("Detected: \(model.displayName)").tag("")
                    } else {
                        Text("Not detected").tag("")
                    }
                    ForEach(MugModel.allCases, id: \.rawValue) { model in
                        Text(verbatim: model.displayName).tag(model.rawValue)
                    }
                }

                if (isConnected || bluetoothManager.isProbingModel) && emberMug.model == nil {
                    LabeledContent {
                        if bluetoothManager.isProbingModel {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Listening…")
                            }
                        } else {
                            Button("Detect") { bluetoothManager.detectModel() }
                        }
                    } label: {
                        Text("Detect automatically")
                        Text("Hold the button on the bottom of the mug until the light blinks blue, then click Detect.")
                    }
                }
            } header: {
                Text("Model")
            } footer: {
                Text("The model sets the capacity used for volume estimates. The mug only senses roughly how full it is, so amounts are estimates.")
                    .foregroundStyle(.secondary)
            }

            if isConnected {
                Section {
                    if let firmware = emberMug.firmware {
                        LabeledContent("Firmware", value: String(firmware.firmware))
                        LabeledContent("Hardware", value: String(firmware.hardware))
                    }
                    if let level = emberMug.liquidLevel {
                        LabeledContent("Level sensor", value: "\(level) / \(Int(EmberMug.fullLiquidLevel))")
                    }
                } header: {
                    Text("Details")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { nameDraft = emberMug.name ?? "" }
        .onChange(of: emberMug.name) { newName in
            nameDraft = newName ?? ""
        }
    }

    private var canSaveName: Bool {
        EmberMug.isValidName(nameDraft) && nameDraft != emberMug.name
    }

    private func saveName() {
        guard canSaveName else { return }
        emberMug.setName(nameDraft)
    }
}

// MARK: - Presets

struct PresetsSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("showPresets") private var showPresets = false
    @AppStorage("showTimers") private var showTimers = true

    var body: some View {
        Form {
            Section {
                Toggle("Show presets in the menu bar window", isOn: $showPresets)
                ForEach($appState.presets, id: \.id) { preset in
                    PresetEntry(
                        preset: preset,
                        onDelete: { appState.presets.removeAll(where: { $0.id == preset.id }) }
                    )
                }
                if appState.presets.count < 4 {
                    Button {
                        appState.presets.append(Preset())
                    } label: {
                        Label("Add preset", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Temperature presets")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("When off, the window shows how much is in the mug and what you drank today instead.")
                    Text("Tip: hold a preset in the menu bar window to save the current target to it.")
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show timers in the menu bar window", isOn: $showTimers)
                ForEach(appState.timers.indices, id: \.self) { index in
                    LabeledContent {
                        HStack(spacing: 10) {
                            Picker("Duration", selection: timerMinutes(at: index)) {
                                ForEach(1...30, id: \.self) { minutes in
                                    Text("\(minutes) min").tag(minutes)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                            Button {
                                appState.timers.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove timer")
                        }
                    } label: {
                        Label("Timer", systemImage: "timer")
                    }
                }
                if appState.timers.count < 4 {
                    Button {
                        appState.timers.append("4:00")
                    } label: {
                        Label("Add timer", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text("Timers")
            }
        }
        .formStyle(.grouped)
    }

    // Timers are stored as "m:ss"; the settings edit them in whole minutes.
    private func timerMinutes(at index: Int) -> Binding<Int> {
        Binding(
            get: {
                // Guard against a stale index while a row is being removed.
                guard appState.timers.indices.contains(index),
                      let seconds = convertTimeToSeconds(appState.timers[index]) else { return 4 }
                return max(1, seconds / 60)
            },
            set: { minutes in
                guard appState.timers.indices.contains(index) else { return }
                appState.timers[index] = formatTime(minutes * 60)
            }
        )
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)

                    Text("EmberBar")
                        .font(.title.weight(.semibold))

                    Text("Version \(Bundle.main.appVersion) (\(Bundle.main.buildNumber))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Based on") {
                    Link("EmberMate by Matthew Nitschke", destination: URL(string: "https://github.com/matthewnitschke/EmberMate")!)
                }
                LabeledContent("License", value: "MIT")
            }
        }
        .formStyle(.grouped)
    }
}

extension Array: RawRepresentable where Element: Codable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        self = result
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

extension URL {
    static let notificationSettings: URL = {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

        guard let bundleId = Bundle.main.bundleIdentifier else {
            return url
        }

        return url.appending(queryItems: [
            .init(name: "id", value: bundleId)
        ])
    }()
}

#if DEBUG
private func previewEnvironment<V: View>(_ view: V, connected: Bool = true) -> some View {
    let mug = EmberMug()
    mug.batteryLevel = 64
    mug.liquidLevel = 18
    mug.setLEDColor(LEDColor(red: 255, green: 120, blue: 30, brightness: 200))
    let manager = BluetoothManager(emberMug: mug)
    if connected { manager.state = .connected }
    let state = AppState()
    return view
        .frame(width: 460, height: 560)
        .environmentObject(mug)
        .environmentObject(state)
        .environmentObject(manager)
        .environmentObject(AutoOffController(appState: state, emberMug: mug))
        .environmentObject(DrinkTracker(emberMug: mug))
}

#Preview("General") { previewEnvironment(GeneralSettingsView()) }
#Preview("Mug") { previewEnvironment(MugSettingsView()) }
#Preview("Presets") { previewEnvironment(PresetsSettingsView()) }
#Preview("General NL") { previewEnvironment(GeneralSettingsView()).environment(\.locale, Locale(identifier: "nl")) }
#endif
