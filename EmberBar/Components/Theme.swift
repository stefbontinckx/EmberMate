//
//  Theme.swift
//  EmberBar
//

import SwiftUI

// Shared look for the menu bar popover: translucent cards on a warm gradient.
enum Theme {
    static let popoverWidth: CGFloat = 320
    static let cornerRadius: CGFloat = 12
    static let cardFill = Color.black.opacity(0.22)
    static let cardFillSelected = Color.black.opacity(0.45)
    static let cardStroke = Color.white.opacity(0.08)
}

struct CardBackground: ViewModifier {
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(isSelected ? Theme.cardFillSelected : Theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(isSelected ? Color.white.opacity(0.7) : Theme.cardStroke, lineWidth: isSelected ? 1.5 : 1)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Circle().fill(Color.black.opacity(configuration.isPressed ? 0.45 : 0.25)))
            .overlay(Circle().strokeBorder(Theme.cardStroke))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// Small capsule button (timer durations).
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.45 : 0.25)))
            .overlay(Capsule().strokeBorder(Theme.cardStroke))
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
