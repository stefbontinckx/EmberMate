//
//  BluetoothManager.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 11/28/23.
//

import CoreBluetooth
import AppKit
import os

private let log = Logger(subsystem: "be.bontinckx.EmberBar", category: "bluetooth")

enum ConnectionState {
    // there is a mug currently connected
    case connected

    // we are actively looking for a mug
    case connecting

    // a mug was previouslly connected, but then
    // was disconnected and we are searching for it
    case reConnecting

    // there is no mug connected
    case disconnected
}

class BluetoothManager: NSObject, ObservableObject {
    // How often we actively poke the mug to prove the link is still alive.
    private let heartbeatInterval: TimeInterval = 5
    // If the mug hasn't responded at all within this window, we treat the
    // connection as stale ("zombie") and force a reconnect.
    private let staleThreshold: TimeInterval = 12

    private var centralManager: CBCentralManager?
    @Published var peripherals: [CBPeripheral] = []

    @Published var state: ConnectionState = .disconnected

    var emberMug: EmberMug

    private var peripheralIdentifier: UUID?
    private var recentlySeen: Set<CBPeripheral> = []
    private var staleTimer: Timer?
    private var heartbeatTimer: Timer?

    init(emberMug: EmberMug) {
        self.emberMug = emberMug
        super.init()

        let existingIdentifier = UserDefaults.standard.string(forKey: "peripheralIdentifier")
        if let existingIdentifier = existingIdentifier {
            self.peripheralIdentifier = UUID(uuidString: existingIdentifier)
        }

        self.centralManager = CBCentralManager(delegate: self, queue: .main)

        // After the machine wakes, BLE connections are frequently stale but
        // macOS still reports them as connected. Give the mug a fresh grace
        // window to respond before the heartbeat starts forcing reconnects.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        guard state == .connected else { return }
        emberMug.markAlive()
        emberMug.ping()
    }

    private func sortPeripherals() {
        peripherals.sort { lhs, rhs in
            let lhsName = lhs.name ?? ""
            let rhsName = rhs.name ?? ""
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.identifier.uuidString < rhs.identifier.uuidString
        }
    }

    func stopScanning() {
        centralManager?.stopScan()
        staleTimer?.invalidate()
        staleTimer = nil
    }

    func startScanning() {
        centralManager?.scanForPeripherals(
            withServices: [EmberMug.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )

        staleTimer?.invalidate()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            var seen = self.recentlySeen
            self.recentlySeen.removeAll()
            if let connected = self.emberMug.peripheral, !seen.contains(connected) {
                seen.insert(connected)
            }
            self.peripherals = Array(seen)
            sortPeripherals()
        }
    }

    func connect(peripheral: CBPeripheral) {
        state = .connecting
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "peripheralIdentifier")
        peripheral.delegate = emberMug
        centralManager?.connect(peripheral)
        startScanning()
    }

    // MARK: - Heartbeat

    // While connected, periodically poke the mug. If it stops responding for
    // longer than `staleThreshold`, the connection is a zombie and we force a
    // reconnect instead of sitting on a link that no longer carries data.
    private func startHeartbeat() {
        stopHeartbeat()
        emberMug.markAlive()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.checkHeartbeat()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func checkHeartbeat() {
        guard state == .connected else { return }

        let elapsed = Date().timeIntervalSince(emberMug.lastResponseTime)
        if elapsed > staleThreshold {
            print("Mug connection stale (\(Int(elapsed))s with no response). Forcing reconnect.")
            forceReconnect()
            return
        }

        emberMug.ping()
    }

    // Cancel the stale link. That triggers `didDisconnectPeripheral`, which
    // re-issues the connection because `state == .reConnecting`.
    private func forceReconnect() {
        guard let peripheral = emberMug.peripheral else { return }
        stopHeartbeat()
        state = .reConnecting
        centralManager?.cancelPeripheralConnection(peripheral)

        // Safety net: if CoreBluetooth doesn't report a disconnect for the
        // zombie link, kick off a connection attempt anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.state == .reConnecting else { return }
            self.centralManager?.connect(peripheral, options: nil)
        }
    }

    @objc func disconnect() {
        stopHeartbeat()
        if let peripheral = emberMug.peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        UserDefaults.standard.removeObject(forKey: "peripheralIdentifier")
        state = .disconnected
    }
}

extension BluetoothManager: CBCentralManagerDelegate {


    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Try to reconnect to a known device
            if let peripheralIdentifier = peripheralIdentifier {
                let peripherals = central.retrievePeripherals(withIdentifiers: [peripheralIdentifier])
                if let peripheral = peripherals.first {
                    self.peripherals.append(peripheral)
                    peripheral.delegate = emberMug
                    central.connect(peripheral, options: nil)
                } else {
                    print("Peripheral not found. Make sure the device is nearby and powered on.")
                }
            } else {
                print("No stored peripheral identifier. Connect to the device for the first time.")
            }

            startScanning()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        recentlySeen.insert(peripheral)
        // Silently pick up model and colour whenever the mug is in pairing mode.
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           let info = MugModel.parse(manufacturerData: data),
           info.model != MugModel.remembered(for: peripheral.identifier)
            || info.colour != MugColour.remembered(for: peripheral.identifier) {
            log.notice("Advertisement \(data.map { String(format: "%02x", $0) }.joined(), privacy: .public) -> \(info.model?.rawValue ?? "unknown", privacy: .public), \(info.colour?.rawValue ?? "unknown", privacy: .public)")
            emberMug.remember(model: info.model, colour: info.colour, for: peripheral.identifier)
        }
        if !peripherals.contains(peripheral) {
            self.peripherals.append(peripheral)
            sortPeripherals()
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        // If we're trying to get back to the mug, keep retrying. Scanning is
        // running while reConnecting, so the mug will also be rediscovered.
        guard state == .reConnecting || state == .connecting else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.state == .reConnecting || self.state == .connecting else { return }
            self.centralManager?.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        stopScanning()
        emberMug.attach(to: peripheral)
        startHeartbeat()
        peripheral.discoverServices([EmberMug.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        stopHeartbeat()

        // Re-connect whenever we were connected (unexpected drop) or are
        // explicitly re-connecting (stale link detected by the heartbeat).
        // A user-initiated disconnect leaves `state == .disconnected`, so we
        // correctly do NOT reconnect in that case.
        if state == .connected || state == .reConnecting {
            state = .reConnecting
            central.connect(emberMug.peripheral ?? peripheral, options: nil)
        }

        startScanning()
    }
}
