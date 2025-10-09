//
//  BackendConfigView.swift
//  FlixorMac
//
//  Initial screen for configuring backend server URL
//

import SwiftUI

struct BackendConfigView: View {
    @StateObject private var viewModel = BackendConfigViewModel()
    @EnvironmentObject var sessionManager: SessionManager
    @State private var navigateToAuth = false

    var body: some View {
        ZStack {
            // Background gradient matching web app
            LinearGradient(
                stops: [
                    .init(color: Color.backgroundPrimary, location: 0),
                    .init(color: Color.backgroundSecondary, location: 0.5),
                    .init(color: Color.backgroundPrimary, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo and Title
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(Color.brand)

                    Text("Welcome to Flixor")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Configure your backend server to get started")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }

                // Configuration Form
                VStack(spacing: 24) {
                    // Backend URL Input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backend Server URL")
                            .font(.headline)
                            .foregroundStyle(.white)

                        TextField("http://localhost:3001", text: $viewModel.backendURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                            .foregroundStyle(.white)
                            .disabled(viewModel.isTestingConnection)
                    }

                    // Test Connection Button
                    Button(action: {
                        Task {
                            await viewModel.testConnection()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if viewModel.isTestingConnection {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "network")
                            }

                            Text(viewModel.isTestingConnection ? "Testing..." : "Test Connection")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.backendURL.isEmpty || viewModel.isTestingConnection)

                    // Connection Status
                    if let status = viewModel.connectionStatus {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(viewModel.isConnected ? .green : .orange)

                            Text(status)
                                .font(.subheadline)
                                .foregroundStyle(viewModel.isConnected ? .green : .orange)
                        }
                        .transition(.opacity)
                    }

                    // Error Message
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    }

                    // Continue Button
                    Button(action: {
                        if viewModel.saveAndContinue() {
                            navigateToAuth = true
                        }
                    }) {
                        Text("Continue to Sign In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(viewModel.isConnected ? Color.brand : Color.gray.opacity(0.3))
                            .foregroundStyle(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.isConnected)
                    .opacity(viewModel.isConnected ? 1.0 : 0.5)
                }
                .frame(width: 400)
                .padding(32)
                .background(Color.white.opacity(0.05))
                .cornerRadius(16)

                Spacer()

                // Help Text
                VStack(spacing: 8) {
                    Text("Need help?")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Make sure your backend server is running with 'npm run dev'")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
            .padding(40)
        }
        .navigationDestination(isPresented: $navigateToAuth) {
            PlexAuthView()
        }
    }
}

#Preview {
    BackendConfigView()
        .environmentObject(SessionManager.shared)
        .frame(width: 800, height: 600)
}
