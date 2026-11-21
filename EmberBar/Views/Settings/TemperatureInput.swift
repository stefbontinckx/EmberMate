//
//  TemperatureInput.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 1/26/25.
//

import Foundation
import SwiftUI
import AppKit
import UserNotifications

// Picks a temperature in the mug's range (half-degree steps), shown in the user's unit.
struct TemperatureInput: View {
    @EnvironmentObject private var emberMug: EmberMug

    @Binding var value: Double

    private static let options = Array(stride(from: EmberMug.minTemp, through: EmberMug.maxTemp, by: 0.5))

    var body: some View {
        Picker("Temperature", selection: Binding(
            get: { (value * 2).rounded() / 2 },
            set: { value = $0 }
        )) {
            ForEach(Self.options, id: \.self) { temp in
                Text(getFormattedTemperature(temp, unit: emberMug.temperatureUnit))
                    .monospacedDigit()
                    .tag(temp)
            }
            // Keep an out-of-range value from an older version selectable.
            if !Self.options.contains((value * 2).rounded() / 2) {
                Text(getFormattedTemperature(value, unit: emberMug.temperatureUnit)).tag((value * 2).rounded() / 2)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}
