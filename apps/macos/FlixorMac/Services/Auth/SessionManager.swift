//
//  SessionManager.swift
//  FlixorMac
//
//  Session management and authentication state
//

import Foundation

@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()

    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Session Restore

    func restoreSession() async {
        // Check if we have a token
        guard apiClient.isAuthenticated else {
            return
        }

        do {
            // Verify session with backend
            let sessionInfo: SessionInfo = try await apiClient.get("/api/auth/session")

            if sessionInfo.authenticated, let user = sessionInfo.user {
                currentUser = user
                isAuthenticated = true
            } else {
                // Token invalid, clear it
                await logout()
            }
        } catch {
            print("Session restore failed: \(error)")
            // Clear invalid session
            await logout()
        }
    }

    // MARK: - Login

    func login(token: String) async throws {
        // Save token
        apiClient.setToken(token)

        // Fetch user info
        let sessionInfo: SessionInfo = try await apiClient.get("/api/auth/session")

        if sessionInfo.authenticated, let user = sessionInfo.user {
            currentUser = user
            isAuthenticated = true
        } else {
            throw APIError.unauthorized
        }
    }

    // MARK: - Logout

    func logout() async {
        apiClient.setToken(nil)
        currentUser = nil
        isAuthenticated = false
    }
}
