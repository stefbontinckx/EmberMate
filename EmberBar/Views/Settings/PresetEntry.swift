//
//  PresetEntry.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 1/27/25.
//

import SwiftUI

struct PresetEntry: View {
    var images: [String] = [
        "mug.fill",
        "cup.and.saucer.fill",
        "drop.fill",
        "leaf.fill",
        "star.fill",
        "flame.fill"
    ]
    
    @Binding var preset: Preset
    var onDelete: () -> Void
    
    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                TemperatureInput(value: $preset.temperature)
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove preset")
            }
        } label: {
            HStack(spacing: 8) {
                Menu {
                    Picker("Icon", selection: $preset.icon) {
                        ForEach(images, id: \.self) { image in
                            Image(systemName: image).tag(image)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Image(systemName: preset.icon)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Icon")

                TextField("Name", text: $preset.name)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
            }
        }
    }
}
