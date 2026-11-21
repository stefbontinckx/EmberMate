//
//  IconButton.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/19/23.
//

import Foundation
import SwiftUI

struct IconButton: View {
    var headerText: String?
    var footerText: String
    var icon: String
    var isSelected: Bool
    var onSelect: () -> Void
    var onLongPress: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(height: 26)

                VStack(spacing: 1) {
                    if let headerText {
                        Text(headerText)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    Text(footerText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .card(selected: isSelected)
            .brightness(isHovering && !isSelected ? 0.08 : 0)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("Click to set, hold to save the current target to this preset")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    onLongPress?()
                }
        )
    }
}
