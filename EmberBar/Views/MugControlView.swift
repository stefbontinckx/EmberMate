//
//  MugControlView.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/5/23.
//

import Foundation
import SwiftUI

struct MugControlView: View {
    @EnvironmentObject private var emberMug: EmberMug
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var autoOff: AutoOffController
    @EnvironmentObject private var drinkTracker: DrinkTracker
    @AppStorage(DrinkTracker.trackingKey) private var trackDrinking = true
    @AppStorage("showPresets") private var showPresets = false
    @AppStorage("showTimers") private var showTimers = true

    @Environment(\.openSettings_backport) private var openSettings
    @Environment(\.dismiss) private var dismiss

    // Range the mug accepts (°C); also used to scale the ring and background.
    private let minTemp = EmberMug.minTemp
    private let maxTemp = EmberMug.maxTemp

    private var isEmpty: Bool { emberMug.liquidState == .empty }

    var body: some View {
        VStack(spacing: 14) {
            header
            if emberMug.canWrite == false {
                lockedBanner
            }
            temperatureControl
                .disabled(emberMug.canWrite == false)

            if showPresets {
                statusChips
                presets
                    .disabled(emberMug.canWrite == false)
            } else {
                infoTiles
                if let deadline = autoOff.deadline {
                    chip(systemImage: "timer") {
                        Text("Off at \(deadline, style: .time)")
                    }
                    .help("Heating stops automatically")
                }
            }

            if showTimers && !appState.timers.isEmpty {
                TimerView()
            }

            if showPresets && trackDrinking && drinkTracker.cupsToday > 0 {
                todaySummary
            }
        }
        .padding(14)
        .frame(width: Theme.popoverWidth)
        .background(
            LinearGradient(colors: backgroundGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .animation(.easeInOut(duration: 0.8), value: emberMug.currentTemp)
                .animation(.easeInOut(duration: 0.8), value: isEmpty)
        )
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark) // UI is designed for a dark look on a warm background
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(emberMug.displayName)
                    .font(.headline)
                Label(emberMug.liquidState.label, systemImage: emberMug.liquidState.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            BatteryView(
                display: .both,
                batteryLevel: emberMug.batteryLevel,
                isCharging: emberMug.isCharging,
                textFont: .caption.monospacedDigit()
            )
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.22)))

            Button {
                if emberMug.isHeatingOff {
                    emberMug.turnHeatingOn()
                } else {
                    appState.selectedPreset = nil
                    emberMug.turnHeatingOff()
                }
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(emberMug.isHeatingOff ? Color.black.opacity(0.22) : Color.white.opacity(0.28)))
            }
            .buttonStyle(.plain)
            .disabled(emberMug.canWrite == false)
            .help(emberMug.isHeatingOff ? "Turn heating on" : "Turn heating off")

            Button {
                dismiss()
                openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.black.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    // MARK: - Temperature

    private var temperatureControl: some View {
        HStack {
            Button { adjustTarget(by: -0.5) } label: { Image(systemName: "minus") }
                .buttonStyle(CircleIconButtonStyle())
                .disabled(!emberMug.isHeatingOff && emberMug.targetTemp <= minTemp)
                .help("Lower target temperature")

            Spacer()

            TemperatureRing(
                progress: isEmpty ? 0 : normalized(emberMug.currentTemp),
                targetProgress: emberMug.isHeatingOff ? nil : normalized(emberMug.targetTemp)
            ) {
                VStack(spacing: 2) {
                    if isEmpty {
                        Image(systemName: "mug")
                            .font(.system(size: 30, weight: .light))
                        Text("Empty")
                            .font(.subheadline.weight(.medium))
                    } else {
                        Text(getFormattedTemperature(emberMug.currentTemp, unit: emberMug.temperatureUnit))
                            .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                            .numericTransition()
                    }
                    Group {
                        if emberMug.isHeatingOff {
                            Text("Heating off")
                        } else {
                            Text("Target \(getFormattedTemperature(emberMug.targetTemp, unit: emberMug.temperatureUnit))")
                        }
                    }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .numericTransition()
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: emberMug.currentTemp)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: emberMug.targetTemp)
            }
            .frame(width: 150, height: 150)

            Spacer()

            Button { adjustTarget(by: 0.5) } label: { Image(systemName: "plus") }
                .buttonStyle(CircleIconButtonStyle())
                .disabled(!emberMug.isHeatingOff && emberMug.targetTemp >= maxTemp)
                .help("Raise target temperature")
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Locked mug

    private var lockedBanner: some View {
        Button {
            appState.selectedSettingsTab = "mug"
            dismiss()
            openSettings()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15))
                VStack(alignment: .leading, spacing: 2) {
                    Text("The mug doesn't accept changes")
                        .font(.subheadline.weight(.semibold))
                    Text("Set it up once in the Ember app on your phone. Click for details.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status

    @ViewBuilder
    private var statusChips: some View {
        let minutes = drinkTracker.minutesToTarget
        if drinkTracker.pouredAt != nil || autoOff.deadline != nil || minutes != nil {
            HStack(spacing: 8) {
                if let minutes {
                    chip(systemImage: emberMug.liquidState == .cooling ? "snowflake" : "flame.fill") {
                        Text("Ready in ~\(minutes) min")
                    }
                    .help("Estimate based on how fast the temperature is changing")
                }
                if let pouredAt = drinkTracker.pouredAt {
                    chip(systemImage: "drop.fill") {
                        Text("Poured at \(pouredAt, style: .time)")
                    }
                }
                if let deadline = autoOff.deadline {
                    chip(systemImage: "timer") {
                        Text("Off at \(deadline, style: .time)")
                    }
                    .help("Heating stops automatically")
                }
            }
        }
    }

    private var todaySummary: some View {
        HStack(spacing: 6) {
            Image(systemName: "cup.and.saucer.fill")
            Text("Today")
            Text("\(drinkTracker.cupsToday) cups")
                .fontWeight(.semibold)
            if drinkTracker.millilitersToday > 0 {
                Text(verbatim: "·")
                Text("about \(drinkTracker.millilitersToday) ml")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 4)
    }

    private func chip<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            content()
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.22)))
    }

    // MARK: - Info tiles

    private var infoTiles: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            tile("Poured", systemImage: "drop.fill") {
                if let pouredAt = drinkTracker.pouredAt {
                    // Refresh the "x min ago" part even when nothing else changes.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let minutes = max(0, Int(context.date.timeIntervalSince(pouredAt) / 60))
                        Text(pouredAt, style: .time) + Text(verbatim: " · ") + Text("\(minutes) min")
                    }
                } else if isEmpty {
                    Text("Empty")
                } else {
                    Text(verbatim: "–")
                }
            }

            tile("Ready", systemImage: readySymbol) {
                if emberMug.isHeatingOff {
                    Text("Heating off")
                } else if emberMug.liquidState == .stableTemperature {
                    Text("Now")
                } else if let minutes = drinkTracker.minutesToTarget {
                    Text("In \(minutes) min")
                } else {
                    Text(verbatim: "–")
                }
            }
            .help("Estimate based on how fast the temperature is changing")

            if trackDrinking {
                tile("Today", systemImage: "cup.and.saucer.fill") {
                    Text("\(drinkTracker.cupsToday) cups")
                }
                tile("Drunk", systemImage: "chart.bar.fill") {
                    if drinkTracker.millilitersToday > 0 {
                        Text("≈ \(drinkTracker.millilitersToday) ml")
                    } else {
                        Text(verbatim: "–")
                    }
                }
            }
        }
    }

    private var readySymbol: String {
        if emberMug.liquidState == .stableTemperature { return "checkmark.circle.fill" }
        return emberMug.liquidState == .cooling ? "snowflake" : "flame.fill"
    }

    private func tile<Value: View>(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            value()
                .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .card()
    }

    // MARK: - Presets

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach(appState.presets, id: \.id) { preset in
                TemperaturePresetButton(
                    preset: preset,
                    temperatureUnit: emberMug.temperatureUnit,
                    isSelected: isActive(preset),
                    onSelect: {
                        appState.selectedPreset = preset
                        emberMug.setTargetTemp(temp: $0)
                    },
                    onLongPress: { _ in
                        if let index = appState.presets.firstIndex(where: { $0.id == preset.id }) {
                            let updatedPreset = Preset(
                                icon: appState.presets[index].icon,
                                name: appState.presets[index].name,
                                temperature: emberMug.targetTemp
                            )
                            updatedPreset.id = appState.presets[index].id
                            appState.presets[index] = updatedPreset
                        }
                    }
                )
            }
        }
    }

    // MARK: - Helpers

    // A preset counts as active when it was picked, or when the mug's target matches it.
    private func isActive(_ preset: Preset) -> Bool {
        if emberMug.isHeatingOff { return false }
        if let selected = appState.selectedPreset { return selected.id == preset.id }
        return abs(preset.temperature - emberMug.targetTemp) < 0.05
    }

    private func adjustTarget(by delta: Double) {
        appState.selectedPreset = nil
        if emberMug.isHeatingOff {
            emberMug.turnHeatingOn()
            return
        }
        let nextTemp = round((emberMug.targetTemp + delta) * 2) / 2
        emberMug.setTargetTemp(temp: min(max(nextTemp, minTemp), maxTemp))
    }

    private func normalized(_ temp: Double) -> Double {
        min(max((temp - minTemp) / (maxTemp - minTemp), 0), 1)
    }

    private var backgroundGradient: [Color] {
        if isEmpty {
            return [getColor(120, 120, 128), getColor(52, 52, 58)]
        }
        return getBackgroundGradient(normalized(emberMug.currentTemp) * (maxTemp - minTemp))
    }
}

// Circular gauge: the arc shows the current temperature, the dot marks the target.
private struct TemperatureRing<Content: View>: View {
    var progress: Double
    var targetProgress: Double?
    @ViewBuilder var content: Content

    // The ring is open at the bottom: it spans 270°.
    private let span = 0.75
    private let lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: span)
                .stroke(Color.black.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))

            Circle()
                .trim(from: 0, to: max(0.001, progress) * span)
                .stroke(
                    AngularGradient(
                        colors: [Color(red: 1, green: 0.85, blue: 0.55), .white],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .opacity(progress > 0 ? 1 : 0)
                .animation(.easeInOut(duration: 0.6), value: progress)

            if let targetProgress {
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) / 2
                let angle = Angle.degrees(135 + 270 * targetProgress)
                Circle()
                    .fill(.white)
                    .frame(width: lineWidth + 5, height: lineWidth + 5)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .position(
                        x: geo.size.width / 2 + radius * cos(angle.radians),
                        y: geo.size.height / 2 + radius * sin(angle.radians)
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: targetProgress)
            }
            }

            content
        }
        .padding(lineWidth / 2)
    }
}

#if DEBUG
private func previewMug(current: Double, target: Double, state: LiquidState) -> EmberMug {
    let mug = EmberMug()
    mug.currentTemp = current
    mug.targetTemp = target
    mug.liquidState = state
    mug.batteryLevel = 72
    mug.liquidLevel = 21
    return mug
}

#Preview("Heating") {
    MugControlView()
        .environmentObject(previewMug(current: 53.4, target: 57.0, state: .heating))
        .environmentObject(AppState())
        .environmentObject(AutoOffController(appState: AppState(), emberMug: EmberMug()))
        .environmentObject(DrinkTracker(emberMug: EmberMug()))
}

#Preview("Empty") {
    MugControlView()
        .environmentObject(previewMug(current: 30, target: 55.0, state: .empty))
        .environmentObject(AppState())
        .environmentObject(AutoOffController(appState: AppState(), emberMug: EmberMug()))
        .environmentObject(DrinkTracker(emberMug: EmberMug()))
}
#endif
