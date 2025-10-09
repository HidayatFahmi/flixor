//
//  TopNavBar.swift
//  FlixorMac
//
//  Top navigation bar with scroll effects and horizontal navigation
//

import SwiftUI

// Import SidebarItem from SidebarView
enum NavItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case library = "Library"
    case myList = "My List"
    case newPopular = "New & Popular"

    var id: String { rawValue }
}

struct TopNavBar: View {
    @Binding var scrollOffset: CGFloat
    @Binding var activeTab: NavItem
    var onNavigate: (NavItem) -> Void
    @EnvironmentObject var sessionManager: SessionManager

    @State private var hoveredItem: NavItem?

    private var isScrolled: Bool {
        scrollOffset < -12
    }

    var body: some View {
        HStack(spacing: 0) {
            // Logo
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("FLIXOR")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .padding(.trailing, 40)

            // Navigation Links
            HStack(spacing: 32) {
                ForEach(NavItem.allCases) { item in
                    NavLink(
                        item: item,
                        isActive: activeTab == item,
                        isHovered: hoveredItem == item,
                        onTap: { onNavigate(item) },
                        onHover: { hovering in
                            hoveredItem = hovering ? item : nil
                        }
                    )
                }
            }

            Spacer()

            // User Profile Menu
            Menu {
                if let user = sessionManager.currentUser {
                    Text(user.username)
                        .font(.headline)

                    Divider()
                }

                Button(action: {
                    onNavigate(.home) // Navigate to settings (we'll map this)
                    // TODO: Open settings - for now just navigate home
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
        .background(navBarBackground)
        .animation(.easeInOut(duration: 0.2), value: isScrolled)
    }

    private var navBarBackground: some View {
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
    }
}

// MARK: - Navigation Link Component
private struct NavLink: View {
    let item: NavItem
    let isActive: Bool
    let isHovered: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onTap) {
            Text(item.rawValue)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(textColor)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
    }

    private var textColor: Color {
        if isActive {
            return .white
        } else if isHovered {
            return .white.opacity(0.8)
        } else {
            return .white.opacity(0.65)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        TopNavBar(
            scrollOffset: .constant(0),
            activeTab: .constant(.home),
            onNavigate: { _ in }
        )
        .environmentObject(SessionManager.shared)

        Spacer()

        TopNavBar(
            scrollOffset: .constant(-100),
            activeTab: .constant(.library),
            onNavigate: { _ in }
        )
        .environmentObject(SessionManager.shared)
    }
    .background(Color.gray)
}
