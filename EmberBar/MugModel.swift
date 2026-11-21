//
//  MugModel.swift
//  EmberBar
//
//  Model detection from the Ember advertisement data, after python-ember-mug.
//

import Foundation

enum MugModel: String, CaseIterable {
    case cup6
    case mug1Small
    case mug1Large
    case mug2Small
    case mug2Large
    case travelMug
    case tumbler

    var displayName: String {
        switch self {
        case .cup6: "Ember Cup (178 ml)"
        case .mug1Small: "Ember Mug (295 ml)"
        case .mug1Large: "Ember Mug (414 ml)"
        case .mug2Small: "Ember Mug 2 (295 ml)"
        case .mug2Large: "Ember Mug 2 (414 ml)"
        case .travelMug: "Ember Travel Mug (355 ml)"
        case .tumbler: "Ember Tumbler (473 ml)"
        }
    }

    var capacityML: Int {
        switch self {
        case .cup6: 178
        case .mug1Small, .mug2Small: 295
        case .travelMug: 355
        case .mug1Large, .mug2Large: 414
        case .tumbler: 473
        }
    }

    // Bluetooth SIG company ID of Ember, and the ID used on test units.
    private static let companyIDs: [[UInt8]] = [[0xC1, 0x03], [0xFF, 0xFF]]

    // `manufacturerData` is CBAdvertisementDataManufacturerDataKey: a 2-byte
    // little-endian company ID followed by the payload.
    init?(manufacturerData data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count > 2, Self.companyIDs.contains(Array(bytes[0..<2])) else { return nil }
        let payload = Array(bytes[2...])

        if payload.count >= 4 {
            let generation = payload[2]
            switch payload[1] {
            case 1: self = generation < 2 ? .mug1Small : .mug2Small
            case 2, 120: self = generation < 2 ? .mug1Large : .mug2Large
            case 3: self = .travelMug
            case 8: self = .cup6
            case 9: self = .tumbler
            default: return nil
            }
            return
        }

        // Short form: the payload is one signed big-endian number.
        var value = 0
        for byte in payload { value = (value << 8) | Int(byte) }
        let bits = payload.count * 8
        if value >= 1 << (bits - 1) { value -= 1 << bits }

        switch value {
        case 1, 2, 3: self = .mug1Small
        case 65: self = .mug1Large
        case -51, -59, -63, -61, -62, 120: self = .mug2Large
        case -60: self = .cup6
        case -127, -126, -125, -124, -123, -122, -120, -117, -57, -56, -55, -53, -52, 83, 131: self = .mug2Small
        default: return nil
        }
    }

    // A mug only advertises while it isn't connected, so remember what we saw per device.
    private static func key(for identifier: UUID) -> String { "mugModel.\(identifier.uuidString)" }

    static func remembered(for identifier: UUID) -> MugModel? {
        UserDefaults.standard.string(forKey: key(for: identifier)).flatMap(MugModel.init(rawValue:))
    }

    static func remember(_ model: MugModel, for identifier: UUID) {
        UserDefaults.standard.set(model.rawValue, forKey: key(for: identifier))
    }
}
