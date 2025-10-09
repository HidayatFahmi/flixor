//
//  FlixorMacApp.swift
//  FlixorMac
//
//  Created by Claude Code
//  Copyright © 2025 Flixor. All rights reserved.
//

import SwiftUI

@main
struct FlixorMacApp: App {
    @StateObject private var sessionManager = SessionManager.shared
    @StateObject private var apiClient = APIClient.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environmentObject(apiClient)
                .frame(minWidth: 1024, minHeight: 768)
                .onAppear {
                    // Auto-login if credentials exist
                    Task {
                        await sessionManager.restoreSession()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            AppCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(sessionManager)
                .environmentObject(apiClient)
        }
        #endif
    }
}

// MARK: - App Commands
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // Remove "New" menu items
        }

        CommandMenu("Playback") {
            Button("Play/Pause") {
                NotificationCenter.default.post(name: .togglePlayPause, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("Skip Forward") {
                NotificationCenter.default.post(name: .skipForward, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("Skip Backward") {
                NotificationCenter.default.post(name: .skipBackward, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let togglePlayPause = Notification.Name("togglePlayPause")
    static let skipForward = Notification.Name("skipForward")
    static let skipBackward = Notification.Name("skipBackward")
}
