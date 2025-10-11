//
//  PlexServersView.swift
//  FlixorMac
//
//  Displays backend-managed Plex servers with active-state controls.
//

import SwiftUI

struct PlexServersView: View {
    @State private var servers: [PlexServer] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isPerformingAction = false
    @State private var selectedServer: PlexServer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if isLoading {
                ProgressView("Loading servers…")
                    .padding(.top, 8)
            } else if let errorMessage {
                messageRow(text: errorMessage, style: .error)
            } else if servers.isEmpty {
                messageRow(text: "No servers found. Use Refresh to try again.", style: .info)
            } else {
                serverList
            }

            if let statusMessage, !statusMessage.isEmpty {
                Divider().padding(.vertical, 4)
                messageRow(text: statusMessage, style: .success)
            }

        }
        .onAppear {
            Task { await loadServers(force: false) }
        }
        .sheet(item: $selectedServer, onDismiss: {
            Task { await loadServers(force: true) }
        }) { server in
            let binding = Binding(get: { selectedServer != nil }, set: { if !$0 { selectedServer = nil } })
            ServerConnectionView(server: server, isPresented: binding) {
                Task { await loadServers(force: true) }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plex Servers")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Servers provisioned by the backend. Select the one you want the app to use for library browsing and playback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: { Task { await loadServers(force: true) } }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading || isPerformingAction)
        }
    }

    @ViewBuilder
    private var serverList: some View {
        if servers.isEmpty {
            messageRow(text: "No servers found. Use Refresh to try again.", style: .info)
        } else {
            List(servers, id: \.id) { server in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(server.name)
                            .font(.headline)

                        if server.isActive == true {
                            badge(text: "Active", tint: .blue)
                        }

                        if server.owned == true {
                            badge(text: "Owned", tint: .green)
                        }
                    }

                    Text(server.baseURLDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let preferred = server.preferredUri, !preferred.isEmpty {
                        Text("Preferred endpoint: \(preferred)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Make Current") {
                            Task { await setActiveServer(server) }
                        }
                        .disabled(server.isActive == true || isPerformingAction)

                        Button("Endpoints…") {
                            selectedServer = server
                        }
                        .disabled(isPerformingAction)

                        Spacer()
                    }
                }
                .padding(.vertical, 6)
            }
            .listStyle(.inset)
            .frame(minHeight: 240)
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.2))
            .foregroundStyle(tint)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private enum MessageStyle { case error, success, info }

    private func messageRow(text: String, style: MessageStyle) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon(for: style))
            Text(text)
        }
        .font(.footnote)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background(for: style))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func icon(for style: MessageStyle) -> String {
        switch style {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func background(for style: MessageStyle) -> Color {
        switch style {
        case .error: return Color.red.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        case .info: return Color.gray.opacity(0.12)
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadServers(force: Bool) async {
        if isLoading { return }
        if !force && !servers.isEmpty { return }

        isLoading = true
        errorMessage = nil
        statusMessage = nil

        do {
            let fetched = try await APIClient.shared.getPlexServers()
            servers = fetched.sorted { ($0.name.lowercased()) < ($1.name.lowercased()) }
        } catch {
            errorMessage = "Failed to load servers. Please try again."
            print("❌ [Settings] Failed to load Plex servers: \(error)")
        }

        isLoading = false
    }

    @MainActor
    private func setActiveServer(_ server: PlexServer) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        statusMessage = "Updating active server…"

        do {
            _ = try await APIClient.shared.setCurrentPlexServer(serverId: server.id)
            statusMessage = "Active server updated to \(server.name)."
            await loadServers(force: true)
        } catch {
            errorMessage = "Unable to set active server."
            print("❌ [Settings] Failed to set active server: \(error)")
        }

        isPerformingAction = false
    }
}
