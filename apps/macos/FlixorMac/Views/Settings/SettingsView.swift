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
    var body: some View {
        Form {
            Text("General settings will go here")
                .foregroundStyle(.secondary)
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
