//
//  TimerView.swift
//  EmberBar
//
//  Created by Matthew Nitschke on 12/10/23.
//

import Foundation
import SwiftUI

struct TimerView: View {
    @EnvironmentObject private var appState: AppState

    @Environment(\.openURL) var openURL
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if appState.notificationsDisabled {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Notifications are disabled. Click to open System Settings.")
                    .onTapGesture {
                        self.openURL(.notificationSettings)
                    }
            } else {
                Image(systemName: "timer")
            }

            if let countdown = appState.countdown {
                Text(formatTime(countdown))
                    .font(.system(.body, design: .rounded).monospacedDigit().weight(.semibold))
                    .numericTransition()
                    .animation(.default, value: countdown)
                Spacer()
                Button {
                    appState.stopTimer()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(PillButtonStyle())
            } else {
                Text("Timer")
                    .font(.subheadline.weight(.medium))
                Spacer()
                ForEach(appState.timers, id: \.self) { time in
                    if let seconds = convertTimeToSeconds(time) {
                        Button(time) {
                            appState.startTimer(seconds)
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .card()
        .task {
            await appState.updateNotificationsDisabled()
        }
    }
}
