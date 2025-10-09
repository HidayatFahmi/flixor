//
//  TopNavBar.swift
//  FlixorMac
//
//  Top navigation bar with scroll effects
//

import SwiftUI

struct TopNavBar: View {
    @Binding var scrollOffset: CGFloat
    @EnvironmentObject var sessionManager: SessionManager

    private var isScrolled: Bool {
        // Make the switch to solid earlier for a crisper effect
        scrollOffset < -12
    }

    var body: some View {
        HStack(spacing: 20) {
            // Logo
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("FLIXOR")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }

            Spacer()

            // User Profile
            Menu {
                if let user = sessionManager.currentUser {
                    Text(user.username)
                        .font(.headline)

                    Divider()
                }

                Button(action: {
                    // Open settings
                }) {
                    Label("Settings", systemImage: "gear")
                }

                Button(action: {
                    Task {
                        await sessionManager.logout()
                    }
                }) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(sessionManager.currentUser?.username.prefix(1).uppercased() ?? "U")
                            .font(.headline)
                            .foregroundStyle(.white)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                if isScrolled {
                    Color.black
                        .transition(.opacity)
                } else {
                    LinearGradient(
                        colors: [Color.black.opacity(0.65), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .transition(.opacity)
                }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isScrolled)
    }
}

#Preview {
    VStack(spacing: 0) {
        TopNavBar(scrollOffset: .constant(0))
            .environmentObject(SessionManager.shared)

        Spacer()

        TopNavBar(scrollOffset: .constant(-100))
            .environmentObject(SessionManager.shared)
    }
    .background(Color.gray)
}
