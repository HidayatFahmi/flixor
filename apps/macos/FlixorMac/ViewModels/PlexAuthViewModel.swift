//
//  PlexAuthViewModel.swift
//  FlixorMac
//
//  View model for Plex authentication
//

import Foundation
import AppKit

@MainActor
class PlexAuthViewModel: ObservableObject {
    @Published var isAuthenticating = false
    @Published var error: String?
    @Published var authToken: String?

    @Published var backendURL: String = UserDefaults.standard.string(forKey: "backendBaseURL") ?? "http://localhost:3001"
    @Published var isTestingBackend = false
    @Published var backendStatus: String?
    @Published var backendHealthy = false

    private let apiClient = APIClient.shared
    private var pollingTask: Task<Void, Never>?

    // MARK: - Backend Testing

    func testBackend() async {
        isTestingBackend = true
        backendStatus = nil
        backendHealthy = false

        // Update API client base URL
        apiClient.setBaseURL(backendURL)

        do {
            let health = try await apiClient.healthCheck()
            backendStatus = "Connected (\(health["status"] ?? "ok"))"
            backendHealthy = true
        } catch {
            backendStatus = "Connection failed"
            backendHealthy = false
        }

        isTestingBackend = false
    }

    // MARK: - Plex Authentication

    struct PINResponse: Codable {
        let id: Int
        let code: String
        let clientId: String
        let authUrl: String
    }

    struct PINCheckResponse: Codable {
        let authenticated: Bool
        let token: String?
    }

    func startAuthentication() async {
        guard !isAuthenticating else {
            print("⚠️ [Auth] Already authenticating, skipping")
            return
        }

        print("🔐 [Auth] Starting authentication flow...")
        isAuthenticating = true
        error = nil

        do {
            // 1. Request PIN from backend
            print("📍 [Auth] Requesting PIN from backend...")
            let pinResponse: PINResponse = try await apiClient.post("/api/auth/plex/pin")
            print("✅ [Auth] Received PIN - ID: \(pinResponse.id), Code: \(pinResponse.code)")
            print("🌐 [Auth] Auth URL: \(pinResponse.authUrl)")

            // 2. Open browser to Plex auth URL
            if let url = URL(string: pinResponse.authUrl) {
                print("🔗 [Auth] Opening browser for authentication...")
                NSWorkspace.shared.open(url)
            } else {
                print("❌ [Auth] Failed to create URL from authUrl")
            }

            // 3. Start polling for authentication
            print("⏳ [Auth] Starting polling for PIN \(pinResponse.id) with clientId \(pinResponse.clientId)...")
            await pollForAuth(pinId: pinResponse.id, clientId: pinResponse.clientId)

        } catch {
            print("❌ [Auth] Authentication failed: \(error)")
            self.error = error.localizedDescription
            isAuthenticating = false
        }
    }

    private func pollForAuth(pinId: Int, clientId: String) async {
        pollingTask?.cancel()

        pollingTask = Task {
            var attempts = 0
            let maxAttempts = 60 // 2 minutes at 2 seconds per attempt

            print("🔄 [Auth] Polling started - ClientID: \(clientId)")

            while attempts < maxAttempts && !Task.isCancelled {
                attempts += 1

                do {
                    // Check PIN status
                    print("🔍 [Auth] Poll attempt \(attempts)/\(maxAttempts) - Checking PIN \(pinId) with clientId \(clientId)...")
                    let response: PINCheckResponse = try await apiClient.get(
                        "/api/auth/plex/pin/\(pinId)",
                        queryItems: [
                            URLQueryItem(name: "clientId", value: clientId),
                            URLQueryItem(name: "mobile", value: "1")
                        ]
                    )

                    print("📡 [Auth] Poll response - Authenticated: \(response.authenticated), Has token: \(response.token != nil)")

                    if response.authenticated, let token = response.token {
                        // Success!
                        print("✅ [Auth] Authentication successful! Token received: \(token.prefix(10))...")
                        authToken = token
                        isAuthenticating = false
                        return
                    } else {
                        print("⏸️ [Auth] Not authenticated yet, waiting...")
                    }

                } catch {
                    print("⚠️ [Auth] Poll attempt \(attempts) failed: \(error)")
                    print("📝 [Auth] Error details: \(error.localizedDescription)")
                }

                // Wait 2 seconds before next attempt
                if attempts < maxAttempts && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }

            // Timeout
            if !Task.isCancelled {
                print("⏱️ [Auth] Polling timeout after \(attempts) attempts")
                error = "Authentication timeout. Please try again."
                isAuthenticating = false
            } else {
                print("🛑 [Auth] Polling cancelled")
            }
        }
    }

    func cancelAuthentication() {
        pollingTask?.cancel()
        isAuthenticating = false
    }
}
