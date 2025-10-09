//
//  RootView.swift
//  FlixorMac
//
//  Root container that switches between login and main app
//

import SwiftUI

// Simple navigation router to manage NavigationPath
final class NavigationRouter: ObservableObject {
    @Published var path = NavigationPath()
}

struct RootView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("backendConfigured") private var isBackendConfigured = false
    @StateObject private var watchlistController = WatchlistController()

    var body: some View {
        Group {
            if sessionManager.isAuthenticated {
                MainView()
                    .transition(.opacity)
            } else if !isBackendConfigured {
                NavigationStack {
                    BackendConfigView()
                }
                .transition(.opacity)
            } else {
                PlexAuthView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: sessionManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: isBackendConfigured)
        .environmentObject(watchlistController)
    }
}

struct MainView: View {
    @State private var selectedTab: NavItem = .home
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var router = NavigationRouter()

    var body: some View {
        NavigationStack(path: $router.path) {
            destinationView(for: selectedTab)
                // Centralize PlayerView presentation here to avoid inheriting padding
                .navigationDestination(for: MediaItem.self) { item in
                    PlayerView(item: item)
                        .toolbar(.hidden, for: .windowToolbar)
                        .ignoresSafeArea(.all, edges: .all)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        }
        .id(selectedTab) // Recreate entire NavigationStack when tab changes
        .environmentObject(router)
        .toolbar {
            // Logo on left
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)

                    Text("FLIXOR")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }.padding(.horizontal, 10)
            }

            // Navigation links in center
            ToolbarItemGroup(placement: .principal) {
                HStack(spacing: 32) {
                    ForEach(NavItem.allCases) { item in
                        ToolbarNavButton(
                            item: item,
                            isActive: selectedTab == item,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = item
                                }
                            }
                        )
                    }
                }.padding(.horizontal, 15)
            }

            // User profile menu on right
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let user = sessionManager.currentUser {
                        Text(user.username)
                            .font(.headline)

                        Divider()
                    }

                    Button(action: {
                        // TODO: Navigate to settings
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
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
    }

    @ViewBuilder
    private func destinationView(for item: NavItem) -> some View {
        switch item {
        case .home:
            HomeView()
        case .search:
            SearchView()
        case .library:
            LibraryView()
        case .myList:
            MyListView()
        case .newPopular:
            NewPopularView()
        }
    }
}

// MARK: - Toolbar Navigation Button
struct ToolbarNavButton: View {
    let item: NavItem
    let isActive: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            Text(item.rawValue)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(textColor)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
    RootView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
}
