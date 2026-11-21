//
//  AutoOffController.swift
//  EmberBar
//
//  Turns the heater off a set time after the mug was filled, so a forgotten
//  last sip isn't kept warm for hours.
//

import Foundation
import Combine

final class AutoOffController: ObservableObject {
    static let choices = [0, 30, 45, 60, 90, 120]

    // When the heater will be switched off, if auto-off is armed.
    @Published private(set) var deadline: Date?
    // True after auto-off switched the heater off, until the mug is emptied.
    @Published private(set) var didTurnOff = false

    private let appState: AppState
    private let emberMug: EmberMug
    private var filledAt: Date?
    private var pendingReset: DispatchWorkItem?
    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState, emberMug: EmberMug) {
        self.appState = appState
        self.emberMug = emberMug

        emberMug.$liquidState
            .removeDuplicates()
            .sink { [weak self] state in self?.liquidStateChanged(state) }
            .store(in: &cancellables)

        appState.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.update() }
            .store(in: &cancellables)

        emberMug.$targetTemp
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func liquidStateChanged(_ state: LiquidState) {
        switch state {
        case .empty:
            // Reset only once the mug stays empty for a minute; lifting it to
            // drink can briefly read as empty.
            guard pendingReset == nil else { break }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingReset = nil
                guard self.emberMug.liquidState.isEmptyOrStandby else { return }
                self.filledAt = nil
                self.didTurnOff = false
                self.update()
            }
            pendingReset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
        case .standby:
            break
        default:
            pendingReset?.cancel()
            pendingReset = nil
            // First sign of liquid: start counting.
            if filledAt == nil {
                filledAt = Date()
            }
        }
        update()
    }

    private func update() {
        let minutes = appState.autoOffMinutes
        // Only act on a live link: the heater state is stale while disconnected, and
        // a write then never reaches the mug.
        guard minutes > 0, let filledAt, !didTurnOff, emberMug.isConnected,
              !emberMug.isHeatingOff, emberMug.canWrite != false else {
            if deadline != nil { deadline = nil }
            return
        }

        let end = filledAt.addingTimeInterval(TimeInterval(minutes * 60))
        if end <= Date() {
            deadline = nil
            didTurnOff = true
            emberMug.turnHeatingOff()
            postNotification(
                id: "autoOff",
                title: String(localized: "Heating stopped"),
                body: String(localized: "\(emberMug.displayName) stopped heating after \(minutes) minutes.")
            )
        } else if deadline != end {
            deadline = end
        }
    }
}
