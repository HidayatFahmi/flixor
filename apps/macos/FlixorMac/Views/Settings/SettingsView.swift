//
//  SettingsView.swift
//  FlixorMac
//
//  Settings screen
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            PlexServersView()
                .tabItem {
                    Label("Plex Servers", systemImage: "server.rack")
                }

            TraktSettingsView()
                .tabItem {
                    Label("Trakt", systemImage: "chart.bar.fill")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 600, height: 400)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("playerBackend") private var selectedBackend: String = PlayerBackend.avplayer.rawValue

    private var playerBackendBinding: Binding<PlayerBackend> {
        Binding(
            get: { PlayerBackend(rawValue: selectedBackend) ?? .avplayer },
            set: { selectedBackend = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section("Playback") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Player Backend")
                        .font(.headline)

                    Picker("", selection: playerBackendBinding) {
                        ForEach(PlayerBackend.allCases) { backend in
                            Text(backend.displayName).tag(backend)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(PlayerBackend.allCases) { backend in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(backend.displayName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                    Text(backend.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)

                    Text("Choose the media player backend. Changes will apply to new playback sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PlexServersView: View {
    var body: some View {
        Form {
            Text("Plex server management will go here")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct TraktSettingsView: View {
    var body: some View {
        Form {
            Text("Trakt integration will go here")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Flixor for macOS")
                .font(.title)

            Text("Version 1.0.0")
                .foregroundStyle(.secondary)

            Text("A native macOS client for Plex Media Server")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    SettingsView()
}
