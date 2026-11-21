//
//  MugModel.swift
//  EmberBar
//
//  Model and colour from the Ember advertisement data, after python-ember-mug.
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

    // Model and colour from CBAdvertisementDataManufacturerDataKey: a 2-byte
    // little-endian company ID followed by the payload. A mug only sends this
    // in pairing mode (button held until the light blinks blue).
    static func parse(manufacturerData data: Data) -> (model: MugModel?, colour: MugColour?)? {
        let bytes = [UInt8](data)
        guard bytes.count > 2, companyIDs.contains(Array(bytes[0..<2])) else { return nil }
        let payload = Array(bytes[2...])

        if payload.count >= 4 {
            let generation = payload[2]
            let model: MugModel? = switch payload[1] {
            case 1: generation < 2 ? .mug1Small : .mug2Small
            case 2, 120: generation < 2 ? .mug1Large : .mug2Large
            case 3: .travelMug
            case 8: .cup6
            case 9: .tumbler
            default: nil
            }
            // python-ember-mug lists both signed and unsigned codes; accept either.
            let colour = MugColour(code: Int(Int8(bitPattern: payload[3]))) ?? MugColour(code: Int(payload[3]))
            return (model, colour)
        }

        // Short form: the payload is one signed big-endian number that encodes both.
        var value = 0
        for byte in payload { value = (value << 8) | Int(byte) }
        let bits = payload.count * 8
        if value >= 1 << (bits - 1) { value -= 1 << bits }

        let model: MugModel? = switch value {
        case 1, 2, 3: .mug1Small
        case 65: .mug1Large
        case -51, -59, -63, -61, -62, 120: .mug2Large
        case -60: .cup6
        case -127, -126, -125, -124, -123, -122, -120, -117, -57, -56, -55, -53, -52, 83, 131: .mug2Small
        default: nil
        }
        return (model, MugColour(code: value))
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

// Finish of the mug, from the same advertisement (codes after python-ember-mug).
enum MugColour: String, CaseIterable {
    case black, white, grey, red, blue, copper, gold, roseGold, stainlessSteel, sandstone, sageGreen

    init?(code: Int) {
        switch code {
        case -127, -63, 1, 14, 65: self = .black
        case -126, -62, 2, 130: self = .white
        case -120, -117, -56, -53, 8, 11: self = .red
        case -131, -125, -61, 3, 51, 83: self = .copper
        case -124, -60: self = .roseGold
        case -123, -59: self = .stainlessSteel
        case -51: self = .sandstone
        case -52: self = .sageGreen
        case -55: self = .grey
        case -57: self = .blue
        case -122: self = .gold
        default: return nil
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .black: "Black"
        case .white: "White"
        case .grey: "Grey"
        case .red: "Red"
        case .blue: "Blue"
        case .copper: "Copper"
        case .gold: "Gold"
        case .roseGold: "Rose Gold"
        case .stainlessSteel: "Stainless Steel"
        case .sandstone: "Sandstone"
        case .sageGreen: "Sage Green"
        }
    }

    private static func key(for identifier: UUID) -> String { "mugColour.\(identifier.uuidString)" }

    static func remembered(for identifier: UUID) -> MugColour? {
        UserDefaults.standard.string(forKey: key(for: identifier)).flatMap(MugColour.init(rawValue:))
    }

    static func remember(_ colour: MugColour, for identifier: UUID) {
        UserDefaults.standard.set(colour.rawValue, forKey: key(for: identifier))
    }
}
