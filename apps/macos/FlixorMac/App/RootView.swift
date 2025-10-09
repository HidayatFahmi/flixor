//
//  RootView.swift
//  FlixorMac
//
//  Root container that switches between login and main app
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("backendConfigured") private var isBackendConfigured = false

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
    }
}

struct MainView: View {
    @State private var selectedTab: SidebarItem = .home

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedItem: $selectedTab)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            NavigationStack {
                destinationView(for: selectedTab)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func destinationView(for item: SidebarItem) -> some View {
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
        case .settings:
            SettingsView()
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
}
