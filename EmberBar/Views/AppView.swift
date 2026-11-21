//
//  AppView.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/3/23.
//

import Foundation
import SwiftUI

struct AppView: View {
    @EnvironmentObject private var bluetoothManager: BluetoothManager
    @Environment(\.openSettings_backport) private var openSettings

    var body: some View {
        Group {
            switch bluetoothManager.state {
            case .connected: MugControlView()
            case .disconnected, .connecting: ConnectMugView()
            case .reConnecting:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Mug lost, reconnecting…")
                        .font(.subheadline)
                }
                .padding(16)
                .frame(width: Theme.popoverWidth)
            }
        }
        .contextMenu {
            Button("Settings") {
                openSettings()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }
}
