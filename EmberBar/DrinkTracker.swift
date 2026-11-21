//
//  DrinkTracker.swift
//  EmberBar
//
//  Estimates when the drink reaches its target temperature, and keeps a
//  simple per-day tally of cups.
//

import Foundation
import Combine

final class DrinkTracker: ObservableObject {
    static let trackingKey = "trackDrinking"

    // Minutes until the drink reaches the target, while heating or cooling.
    @Published private(set) var minutesToTarget: Int?
    @Published private(set) var cupsToday = 0
    // When the current drink was poured (nil while the mug is empty).
    @Published private(set) var pouredAt: Date?

    private let emberMug: EmberMug
    private var samples: [(time: Date, temp: Double)] = []
    private var isFilled = false
    private var pendingFinish: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private var isTracking: Bool {
        UserDefaults.standard.object(forKey: Self.trackingKey) as? Bool ?? true
    }

    init(emberMug: EmberMug) {
        self.emberMug = emberMug
        loadToday()

        emberMug.$currentTemp
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] temp in self?.record(temp) }
            .store(in: &cancellables)

        emberMug.$targetTemp
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateEstimate() }
            .store(in: &cancellables)

        emberMug.$liquidState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.liquidChanged(state) }
            .store(in: &cancellables)

        // Roll the day over even when nothing else happens.
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadToday()
                self?.updateEstimate()
            }
            .store(in: &cancellables)
    }

    // MARK: - Time to target

    // Assumed room temperature for the cooling curve (°C).
    private static let roomTemp = 22.0

    private func record(_ temp: Double) {
        guard temp > 0 else { return }
        let now = Date()
        samples.append((now, temp))
        // Only the last two minutes count, so an early bump (e.g. the sensor
        // warming up right after pouring) doesn't hide the real trend for long.
        samples.removeAll { now.timeIntervalSince($0.time) > 120 }
        updateEstimate()
    }

    // Least-squares slope of the recent samples, in °C per second.
    private var slope: Double? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last,
              last.time.timeIntervalSince(first.time) >= 30 else { return nil }
        let xs = samples.map { $0.time.timeIntervalSince(first.time) }
        let ys = samples.map(\.temp)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var numerator = 0.0, denominator = 0.0
        for (x, y) in zip(xs, ys) {
            numerator += (x - meanX) * (y - meanY)
            denominator += (x - meanX) * (x - meanX)
        }
        return denominator > 0 ? numerator / denominator : nil
    }

    private func updateEstimate() {
        let estimate = computeEstimate()
        if minutesToTarget != estimate { minutesToTarget = estimate }
    }

    private func computeEstimate() -> Int? {
        let state = emberMug.liquidState
        let target = emberMug.targetTemp
        let current = emberMug.currentTemp
        let gap = target - current

        guard !emberMug.isHeatingOff, state == .heating || state == .cooling, abs(gap) >= 0.3,
              let slope, slope != 0, (gap > 0) == (slope > 0) else { return nil }

        let seconds: Double
        if gap < 0 && target > Self.roomTemp + 1 && current > Self.roomTemp + 1 {
            // Cooling follows Newton's law: it slows down as the drink nears room
            // temperature, so a straight line would be too optimistic.
            let k = -slope / (current - Self.roomTemp)
            seconds = log((current - Self.roomTemp) / (target - Self.roomTemp)) / k
        } else {
            // The heater adds heat at a fairly steady rate.
            seconds = gap / slope
        }

        guard seconds.isFinite, seconds > 0 else { return nil }
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        return minutes > 120 ? nil : minutes
    }

    // MARK: - Daily log

    private func liquidChanged(_ state: LiquidState) {
        switch state {
        case .empty:
            // Only count the cup once the mug stays empty for a minute, so lifting
            // it for a sip (which can briefly read as empty) doesn't count.
            guard isFilled, pendingFinish == nil else { break }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingFinish = nil
                guard self.emberMug.liquidState.isEmptyOrStandby else { return }
                self.finishCup()
                self.isFilled = false
                self.pouredAt = nil
            }
            pendingFinish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
        case .standby:
            break
        default:
            pendingFinish?.cancel()
            pendingFinish = nil
            if !isFilled {
                // A new pour: readings from the empty mug say nothing about this drink.
                samples.removeAll()
                pouredAt = Date()
            }
            isFilled = true
        }
        updateEstimate()
    }

    private func finishCup() {
        guard isTracking else { return }
        loadToday()
        cupsToday += 1
        save()
    }

    func resetToday() {
        cupsToday = 0
        save()
    }

    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func loadToday() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "drinkLog.day") != Self.todayKey {
            defaults.set(Self.todayKey, forKey: "drinkLog.day")
            defaults.set(0, forKey: "drinkLog.cups")
        }
        let cups = defaults.integer(forKey: "drinkLog.cups")
        if cups != cupsToday { cupsToday = cups }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(Self.todayKey, forKey: "drinkLog.day")
        defaults.set(cupsToday, forKey: "drinkLog.cups")
    }
}
