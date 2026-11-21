//
//  EmberMug.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/2/23.
//
//  Protocol reference: github.com/orlopau/ember-mug and github.com/sopelj/python-ember-mug
//

import Foundation
import CoreBluetooth
import Combine
import SwiftUI
import os

private let log = Logger(subsystem: "be.bontinckx.EmberBar", category: "mug")

enum LiquidState: Int {
    case standby = 0
    case empty = 1
    case filling = 2
    case coldNoTempControl = 3
    case cooling = 4
    case heating = 5
    case stableTemperature = 6
    case warmNoTempControl = 7
}

enum TemperatureUnit: Int {
    case celsius = 0
    case fahrenheit = 1
}

// LED colour as the mug stores it: red, green, blue and brightness bytes.
struct LEDColor: Equatable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var brightness: UInt8 = 255

    init(red: UInt8, green: UInt8, blue: UInt8, brightness: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.brightness = brightness
    }

    init?(_ color: Color, brightness: UInt8 = 255) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt8 {
            UInt8((max(0, min(1, component)) * 255).rounded())
        }
        self.init(red: byte(rgb.redComponent), green: byte(rgb.greenComponent), blue: byte(rgb.blueComponent), brightness: brightness)
    }

    var color: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    func sameHue(as other: LEDColor) -> Bool {
        red == other.red && green == other.green && blue == other.blue
    }

    var bytes: [UInt8] { [red, green, blue, brightness] }
}

struct FirmwareInfo: Equatable {
    var firmware: Int
    var hardware: Int
    var bootloader: Int
}

// Characteristics of the main Ember service we use. UUID = fc54XXXX-236c-4c94-8fa9-944a3e5353fa.
private enum MugCharacteristic: UInt16, CaseIterable {
    case name = 0x0001
    case currentTemp = 0x0002
    case targetTemp = 0x0003
    case temperatureUnit = 0x0004
    case liquidLevel = 0x0005
    case battery = 0x0007
    case liquidState = 0x0008
    case firmware = 0x000C
    case pushEvents = 0x0012
    case color = 0x0014

    var uuid: CBUUID {
        CBUUID(string: String(format: "fc54%04x-236c-4c94-8fa9-944a3e5353fa", rawValue))
    }

    init?(uuid: CBUUID) {
        guard let match = Self.allCases.first(where: { $0.uuid == uuid }) else { return nil }
        self = match
    }
}

private enum PushEvent: UInt8 {
    case batteryChanged = 1
    case chargerConnected = 2
    case chargerDisconnected = 3
    case targetTempChanged = 4
    case currentTempChanged = 5
    case liquidLevelChanged = 7
    case liquidStateChanged = 8
}

class EmberMug: NSObject, ObservableObject, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "fc543622-236c-4c94-8fa9-944a3e5353fa")

    // Range the mug accepts for a target temperature (°C). Writing 0 turns the heater off.
    static let minTemp = 50.0
    static let maxTemp = 63.0
    // Liquid level reported by a mug when it is full (orlopau: 0 = empty, 30 = not empty).
    static let fullLiquidLevel = 30.0

    private static let temperatureUnitKey = "temperatureUnit"
    private static let lastTargetKey = "lastTargetTemp"
    // Only written when the user picks a target in EmberBar.
    private static let preferredTargetKey = "preferredTargetTemp"
    static let modelOverrideKey = "mugModelOverride"

    @Published var batteryLevel: Int = 0 // 5 - 100
    @Published var isCharging: Bool = false
    @Published var currentTemp: Double = 0.0
    @Published var targetTemp: Double = 0.0
    @Published var liquidState: LiquidState = LiquidState.empty
    @Published var liquidLevel: Int?
    // The unit the app displays. This is the user's choice and is persisted
    // locally; the mug's own setting is kept in sync with it, not the other
    // way around (the mug can fall back to °F, e.g. after a reset or when the
    // Ember phone app writes to it).
    @Published private(set) var temperatureUnit: TemperatureUnit
    @Published private(set) var ledColor: LEDColor?
    @Published private(set) var name: String?
    @Published private(set) var firmware: FirmwareInfo?
    @Published private(set) var model: MugModel?

    var peripheral: CBPeripheral?

    // The last time we received *any* response from the mug over BLE.
    // Used by BluetoothManager's heartbeat to detect a stale ("zombie")
    // connection where macOS still reports `connected` but nothing is
    // actually coming back over the link.
    private(set) var lastResponseTime: Date = Date()

    private var characteristics: [MugCharacteristic: CBCharacteristic] = [:]

    // LED writes are debounced so dragging the brightness slider doesn't flood the mug.
    private let ledWrites = PassthroughSubject<LEDColor, Never>()

    private var cancellables: Set<AnyCancellable> = []

    private var preferredTemperatureUnit: TemperatureUnit? {
        guard UserDefaults.standard.object(forKey: Self.temperatureUnitKey) != nil else { return nil }
        return TemperatureUnit(rawValue: UserDefaults.standard.integer(forKey: Self.temperatureUnitKey))
    }

    // The heater is off when the mug's target temperature is 0.
    var isHeatingOff: Bool { targetTemp < 1 }

    var displayName: String {
        name ?? peripheral?.name ?? "Ember"
    }

    // The target the user picked in EmberBar. It wins over whatever the mug
    // reports (the mug or the Ember phone app can put back another value).
    private var preferredTarget: Double? {
        guard UserDefaults.standard.object(forKey: Self.preferredTargetKey) != nil else { return nil }
        let value = UserDefaults.standard.double(forKey: Self.preferredTargetKey)
        return (Self.minTemp...Self.maxTemp).contains(value) ? value : nil
    }

    var lastActiveTarget: Double {
        if let preferredTarget { return preferredTarget }
        let stored = UserDefaults.standard.double(forKey: Self.lastTargetKey)
        return (Self.minTemp...Self.maxTemp).contains(stored) ? stored : 55
    }

    // The model picked in Settings, otherwise the one read from the mug.
    var effectiveModel: MugModel? {
        UserDefaults.standard.string(forKey: Self.modelOverrideKey).flatMap(MugModel.init(rawValue:)) ?? model
    }

    var capacityML: Int? {
        effectiveModel?.capacityML
    }

    // How full the mug is (0...1), from the coarse level sensor.
    var estimatedFillFraction: Double? {
        guard liquidState != .empty, let level = liquidLevel, level > 0 else { return nil }
        return min(max(Double(level) / Self.fullLiquidLevel, 0), 1)
    }

    // Rough estimate of what's left in the mug. The level sensor is coarse,
    // so this is only an indication.
    var estimatedVolumeML: Int? {
        guard let fraction = estimatedFillFraction, let capacity = capacityML else { return nil }
        // Round to 10 ml so the number doesn't suggest more precision than there is.
        return Int((fraction * Double(capacity) / 10).rounded()) * 10
    }

    override init() {
        // Fall back to the locale's convention until the user has picked a unit.
        let localeDefault: TemperatureUnit = Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        let stored = UserDefaults.standard.object(forKey: Self.temperatureUnitKey) as? Int
        self.temperatureUnit = stored.flatMap(TemperatureUnit.init(rawValue:)) ?? localeDefault

        super.init()

        ledWrites
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] led in
                self?.write(Data(led.bytes), to: .color)
            }
            .store(in: &cancellables)
    }

    // MARK: - Connection lifecycle

    // Called by BluetoothManager when a (new) connection is made.
    func attach(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        characteristics = [:]
        model = MugModel.remembered(for: peripheral.identifier)
    }

    func rememberModel(_ model: MugModel, for identifier: UUID) {
        MugModel.remember(model, for: identifier)
        if peripheral?.identifier == identifier {
            self.model = model
        }
    }

    // Record that the mug talked to us, so the heartbeat considers the link alive.
    func markAlive() {
        lastResponseTime = Date()
    }

    // Actively solicit a response from the mug. If the connection is stale the
    // read either never completes or never calls back, so `lastResponseTime`
    // stops advancing and the BluetoothManager forces a reconnect.
    func ping() {
        if characteristics[.currentTemp] != nil {
            read(.currentTemp)
            read(.liquidLevel)
        } else {
            read(.battery)
        }
    }

    // MARK: - Writes

    private func write(_ data: Data, to kind: MugCharacteristic) {
        guard let peripheral, let characteristic = characteristics[kind] else { return }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func read(_ kind: MugCharacteristic) {
        guard let peripheral, let characteristic = characteristics[kind] else { return }
        peripheral.readValue(for: characteristic)
    }

    private func writeTarget(_ temp: Double) {
        let value = UInt16((temp * 100).rounded())
        write(Data([UInt8(value & 0xFF), UInt8(value >> 8)]), to: .targetTemp)
    }

    func setTargetTemp(temp: Double) {
        // Stay within the range the Ember app allows, so nobody breaks their mug.
        guard (Self.minTemp...Self.maxTemp).contains(temp) else { return }

        targetTemp = temp
        UserDefaults.standard.set(temp, forKey: Self.lastTargetKey)
        UserDefaults.standard.set(temp, forKey: Self.preferredTargetKey)
        writeTarget(temp)
    }

    func turnHeatingOff() {
        targetTemp = 0
        writeTarget(0)
    }

    func turnHeatingOn() {
        setTargetTemp(temp: lastActiveTarget)
    }

    // Called when the user picks a unit: remember it and push it to the mug.
    func setTemperatureUnit(_ unit: TemperatureUnit) {
        UserDefaults.standard.set(unit.rawValue, forKey: Self.temperatureUnitKey)
        temperatureUnit = unit
        write(Data([UInt8(unit.rawValue)]), to: .temperatureUnit)
    }

    // The mug accepts 1–16 characters from a limited set.
    static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[A-Za-z0-9 ,.\[\]#()!"';:|\-_+<>%=]{1,16}$"#, options: .regularExpression) != nil
    }

    func setName(_ newName: String) {
        guard Self.isValidName(newName) else { return }
        name = newName
        write(Data(newName.utf8), to: .name)
    }

    func setLEDColor(_ led: LEDColor) {
        ledColor = led
        ledWrites.send(led)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        markAlive()
        self.peripheral = peripheral
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(MugCharacteristic.allCases.map(\.uuid), for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        markAlive()
        for characteristic in service.characteristics ?? [] {
            guard let kind = MugCharacteristic(uuid: characteristic.uuid) else { continue }
            characteristics[kind] = characteristic

            if kind == .pushEvents {
                peripheral.setNotifyValue(true, for: characteristic)
            } else {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        markAlive()
        guard let kind = MugCharacteristic(uuid: characteristic.uuid),
              let data = characteristic.value, !data.isEmpty else { return }

        switch kind {
        case .targetTemp:
            let reported = Double(data.extractUInt16()) * 0.01
            if let preferred = preferredTarget, reported >= 1, abs(reported - preferred) > 0.05 {
                // Heating is on but at another target than the user chose: put theirs back.
                log.notice("Mug reported target \(reported, privacy: .public), restoring \(preferred, privacy: .public)")
                targetTemp = preferred
                writeTarget(preferred)
            } else {
                // 0 means heating is off (by the user or auto-off): leave that alone.
                targetTemp = reported
                if preferredTarget == nil, (Self.minTemp...Self.maxTemp).contains(reported) {
                    UserDefaults.standard.set(reported, forKey: Self.lastTargetKey)
                }
            }
        case .currentTemp:
            currentTemp = Double(data.extractUInt16()) * 0.01
        case .battery:
            guard data.count >= 2 else { return }
            batteryLevel = Int(data[0])
            isCharging = data[1] == 1
        case .liquidState:
            if let state = LiquidState(rawValue: Int(data[0])) {
                liquidState = state
            }
        case .liquidLevel:
            liquidLevel = Int(data[0])
        case .temperatureUnit:
            guard let mugUnit = TemperatureUnit(rawValue: Int(data[0])) else { return }
            if let preferred = preferredTemperatureUnit {
                // The user's choice wins: correct the mug if it drifted.
                if mugUnit != preferred {
                    write(Data([UInt8(preferred.rawValue)]), to: .temperatureUnit)
                }
            } else {
                // No explicit choice yet: show what the mug uses.
                temperatureUnit = mugUnit
            }
        case .color:
            guard data.count >= 4 else { return }
            ledColor = LEDColor(red: data[0], green: data[1], blue: data[2], brightness: data[3])
        case .name:
            let decoded = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            name = decoded.isEmpty ? nil : decoded
        case .firmware:
            guard data.count >= 4 else { return }
            let bytes = [UInt8](data)
            firmware = FirmwareInfo(
                firmware: Int(data.extractUInt16()),
                hardware: Int(Data(bytes[2...]).extractUInt16()),
                bootloader: bytes.count >= 6 ? Int(Data(bytes[4...]).extractUInt16()) : 0
            )
        case .pushEvents:
            handle(PushEvent(rawValue: data[0]))
        }
    }

    private func handle(_ event: PushEvent?) {
        switch event {
        case .batteryChanged: read(.battery)
        case .chargerConnected: isCharging = true
        case .chargerDisconnected: isCharging = false
        case .targetTempChanged: read(.targetTemp)
        case .currentTempChanged: read(.currentTemp)
        case .liquidLevelChanged: read(.liquidLevel)
        case .liquidStateChanged:
            read(.liquidState)
            read(.liquidLevel)
        case nil: break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        markAlive()
        // Read the name back so we show what the mug actually stored.
        if MugCharacteristic(uuid: characteristic.uuid) == .name {
            read(.name)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        markAlive()
    }
}

extension Data {
    // Little-endian UInt16 from the first two bytes (missing bytes count as 0).
    func extractUInt16() -> UInt16 {
        let bytes = Array(prefix(2))
        let low = UInt16(bytes.first ?? 0)
        let high = UInt16(bytes.count > 1 ? bytes[1] : 0)
        return low | (high << 8)
    }
}
