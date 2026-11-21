//
//  DrinkTracker.swift
//  EmberBar
//
//  Estimates when the drink reaches its target temperature, and keeps a
//  simple per-day tally of cups and millilitres. Both are estimates.
//

import Foundation
import Combine

final class DrinkTracker: ObservableObject {
    static let trackingKey = "trackDrinking"

    // Minutes until the drink reaches the target, while heating or cooling.
    @Published private(set) var minutesToTarget: Int?
    @Published private(set) var cupsToday = 0
    @Published private(set) var millilitersToday = 0

    private let emberMug: EmberMug
    private var samples: [(time: Date, temp: Double)] = []
    private var fillVolume: Int?
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

        Publishers.CombineLatest(emberMug.$liquidState, emberMug.$liquidLevel)
            .receive(on: RunLoop.main)
            .sink { [weak self] state, _ in self?.liquidChanged(state) }
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

    private func record(_ temp: Double) {
        guard temp > 0 else { return }
        let now = Date()
        samples.append((now, temp))
        // A few minutes of history is enough to see the trend.
        samples.removeAll { now.timeIntervalSince($0.time) > 240 }
        updateEstimate()
    }

    private func updateEstimate() {
        let state = emberMug.liquidState
        let target = emberMug.targetTemp
        let current = emberMug.currentTemp
        let gap = target - current

        guard !emberMug.isHeatingOff, state == .heating || state == .cooling, abs(gap) >= 0.3,
              let first = samples.first, let last = samples.last else {
            if minutesToTarget != nil { minutesToTarget = nil }
            return
        }

        let elapsed = last.time.timeIntervalSince(first.time)
        let rate = (last.temp - first.temp) / max(elapsed, 1) // °C per second
        // Need at least half a minute of data moving in the right direction.
        guard elapsed >= 30, rate != 0, (gap > 0) == (rate > 0) else {
            if minutesToTarget != nil { minutesToTarget = nil }
            return
        }

        let minutes = max(1, Int((gap / rate / 60).rounded(.up)))
        let estimate = minutes > 90 ? nil : minutes
        if minutesToTarget != estimate { minutesToTarget = estimate }
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
                guard self.emberMug.liquidState == .empty else { return }
                self.finishCup()
                self.isFilled = false
                self.fillVolume = nil
            }
            pendingFinish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
        case .standby:
            break
        default:
            pendingFinish?.cancel()
            pendingFinish = nil
            isFilled = true
            // The highest reading during a fill is the best guess of what was poured.
            if let volume = emberMug.estimatedVolumeML {
                fillVolume = max(fillVolume ?? 0, volume)
            }
        }
        updateEstimate()
    }

    private func finishCup() {
        guard isTracking else { return }
        loadToday()
        cupsToday += 1
        millilitersToday += fillVolume ?? 0
        save()
    }

    func resetToday() {
        cupsToday = 0
        millilitersToday = 0
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
            defaults.set(0, forKey: "drinkLog.ml")
        }
        let cups = defaults.integer(forKey: "drinkLog.cups")
        let ml = defaults.integer(forKey: "drinkLog.ml")
        if cups != cupsToday { cupsToday = cups }
        if ml != millilitersToday { millilitersToday = ml }
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(Self.todayKey, forKey: "drinkLog.day")
        defaults.set(cupsToday, forKey: "drinkLog.cups")
        defaults.set(millilitersToday, forKey: "drinkLog.ml")
    }
}
