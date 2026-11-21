//
//  ConnectMugView.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/4/23.
//

import Foundation
import SwiftUI
import CoreBluetooth

struct ConnectMugView: View {
    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Image(systemName: "mug.fill")
                    .font(.system(size: 34))
                Text("Connect your mug")
                    .font(.title3.weight(.semibold))
                Text("Hold the button on the bottom of the mug until the light blinks blue.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            SelectDeviceView()
        }
        .padding(18)
        .frame(width: Theme.popoverWidth)
        .background(LinearGradient(
            colors: [getColor(234, 182, 125), getColor(186, 102, 56)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

struct SelectDeviceView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @State private var selectedMug: CBPeripheral?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(bluetoothManager.peripherals, id: \.self) { peripheral in
                Button {
                    guard selectedMug == nil else { return }
                    selectedMug = peripheral
                    bluetoothManager.connect(peripheral: peripheral)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mug")
                            .font(.system(size: 18))
                        Text(peripheral.name ?? "Unknown device")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if selectedMug == peripheral {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Connect")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .card(selected: selectedMug == peripheral)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Searching for mugs…")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 2)
        }
    }
}

#if DEBUG
#Preview {
    ConnectMugView()
        .environmentObject(BluetoothManager(emberMug: EmberMug()))
}
#endif
