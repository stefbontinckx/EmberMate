//
//  Theme.swift
//  EmberBar
//

import SwiftUI

// Shared look for the menu bar popover: translucent cards on a coloured
// gradient. The popover is dark (white text) except for an empty white mug,
// which gets a light look with dark text; `colorScheme` tells them apart.
enum Theme {
    static let popoverWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 12

    // Text colour on the popover background.
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color(red: 0.13, green: 0.13, blue: 0.15) : .white
    }

    // Darkening layer for cards and buttons; much lighter on the light look.
    static func wash(_ amount: Double, _ scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .light ? amount * 0.3 : amount)
    }

    static func stroke(_ scheme: ColorScheme) -> Color {
        scheme == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.08)
    }
}

struct CardBackground: ViewModifier {
    var isSelected: Bool = false
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.wash(isSelected ? 0.45 : 0.22, scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.ink(scheme).opacity(0.7) : Theme.stroke(scheme), lineWidth: isSelected ? 1.5 : 1)
            )
    }
}

extension View {
    func card(selected: Bool = false) -> some View {
        modifier(CardBackground(isSelected: selected))
    }

    // Rolling digits on macOS 14+, a plain update on macOS 13.
    @ViewBuilder
    func numericTransition() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}

// Round +/- button used next to the temperature ring.
struct CircleIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.ink(scheme))
            .frame(width: 38, height: 38)
            .background(Circle().fill(Theme.wash(configuration.isPressed ? 0.45 : 0.25, scheme)))
            .overlay(Circle().strokeBorder(Theme.stroke(scheme)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Small capsule button (timer durations).
struct PillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.ink(scheme))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.wash(configuration.isPressed ? 0.45 : 0.25, scheme)))
            .overlay(Capsule().strokeBorder(Theme.stroke(scheme)))
    }
}

extension LiquidState {
    var label: LocalizedStringKey {
        switch self {
        case .standby: "Standby"
        case .empty: "Empty"
        case .filling: "Filling"
        case .coldNoTempControl: "Cold"
        case .cooling: "Cooling down"
        case .heating: "Heating up"
        case .stableTemperature: "Perfect temperature"
        case .warmNoTempControl: "Warm"
        }
    }

    var symbol: String {
        switch self {
        case .standby: "moon.zzz.fill"
        case .empty: "mug"
        case .filling: "drop.fill"
        case .coldNoTempControl: "snowflake"
        case .cooling: "arrow.down.circle.fill"
        case .heating: "flame.fill"
        case .stableTemperature: "checkmark.circle.fill"
        case .warmNoTempControl: "thermometer.medium"
        }
    }
}
