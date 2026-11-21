//
//  LEDColorPicker.swift
//  EmberBar
//
//  Swatches plus a brightness slider for the mug's LED, instead of the
//  floating macOS colour panel.
//

import SwiftUI

struct LEDColorPicker: View {
    @EnvironmentObject private var emberMug: EmberMug

    private static let swatches: [LEDColor] = [
        LEDColor(red: 255, green: 255, blue: 255),
        LEDColor(red: 255, green: 190, blue: 120),
        LEDColor(red: 255, green: 120, blue: 30),
        LEDColor(red: 255, green: 40, blue: 40),
        LEDColor(red: 255, green: 60, blue: 160),
        LEDColor(red: 160, green: 70, blue: 255),
        LEDColor(red: 40, green: 110, blue: 255),
        LEDColor(red: 0, green: 200, blue: 200),
        LEDColor(red: 40, green: 220, blue: 90),
    ]

    private var current: LEDColor {
        emberMug.ledColor ?? LEDColor(red: 255, green: 255, blue: 255)
    }

    private var isCustom: Bool {
        !Self.swatches.contains { $0.sameHue(as: current) }
    }

    var body: some View {
        LabeledContent("Color") {
            HStack(spacing: 8) {
                ForEach(Array(Self.swatches.enumerated()), id: \.offset) { _, swatch in
                    swatchButton(swatch)
                }

            }
        }

        LabeledContent("Custom color") {
            ColorPicker(
                "Custom color",
                selection: Binding(
                    get: { isCustom ? current.color : Color.gray },
                    set: { pick($0) }
                ),
                supportsOpacity: false
            )
            .labelsHidden()
        }

        LabeledContent("Brightness") {
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(current.brightness) },
                        set: { value in
                            var led = current
                            led.brightness = UInt8(value.rounded())
                            emberMug.setLEDColor(led)
                        }
                    ),
                    in: 10...255
                )
                .frame(maxWidth: 200)
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func swatchButton(_ swatch: LEDColor) -> some View {
        let selected = swatch.sameHue(as: current)
        return Button {
            var led = swatch
            led.brightness = current.brightness
            emberMug.setLEDColor(led)
        } label: {
            Circle()
                .fill(swatch.color)
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ color: Color) {
        guard var led = LEDColor(color) else { return }
        led.brightness = current.brightness
        emberMug.setLEDColor(led)
    }
}
