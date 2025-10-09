//
//  BackendConfigViewModel.swift
//  FlixorMac
//
//  View model for backend URL configuration
//

import Foundation

@MainActor
class BackendConfigViewModel: ObservableObject {
    @Published var backendURL: String = ""
    @Published var isTestingConnection = false
    @Published var connectionStatus: String?
    @Published var isConnected = false
    @Published var errorMessage: String?

    private let apiClient = APIClient.shared

    init() {
        // Load saved URL or use default
        backendURL = UserDefaults.standard.string(forKey: "backendBaseURL") ?? "http://localhost:3001"
    }

    // MARK: - Test Connection

    func testConnection() async {
        isTestingConnection = true
        connectionStatus = nil
        isConnected = false
        errorMessage = nil

        // Update API client base URL
        apiClient.setBaseURL(backendURL)

        do {
            _ = try await apiClient.healthCheck()
            connectionStatus = "✓ Connected successfully"
            isConnected = true

            // Save to UserDefaults on successful connection
            UserDefaults.standard.set(backendURL, forKey: "backendBaseURL")

        } catch {
            connectionStatus = "✗ Connection failed"
            errorMessage = "Unable to connect to backend. Please check the URL and ensure the server is running."
            isConnected = false
        }

        isTestingConnection = false
    }

    // MARK: - Save and Continue

    func saveAndContinue() -> Bool {
        guard isConnected else { return false }

        // Save to UserDefaults
        UserDefaults.standard.set(backendURL, forKey: "backendBaseURL")
        UserDefaults.standard.set(true, forKey: "backendConfigured")

        return true
    }
}
