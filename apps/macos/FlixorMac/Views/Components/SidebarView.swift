//
//  SidebarView.swift
//  FlixorMac
//
//  Navigation sidebar
//

import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case search = "Search"
    case library = "Library"
    case myList = "My List"
    case newPopular = "New & Popular"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "film.stack.fill"
        case .myList: return "star.fill"
        case .newPopular: return "flame.fill"
        case .settings: return "gear"
        }
    }
}

struct SidebarView: View {
    @Binding var selectedItem: SidebarItem
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        List(selection: $selectedItem) {
            Section {
                ForEach(SidebarItem.allCases.filter { $0 != .settings }) { item in
                    NavigationLink(value: item) {
                        Label(item.rawValue, systemImage: item.icon)
                    }
                }
            }

            Section {
                NavigationLink(value: SidebarItem.settings) {
                    Label("Settings", systemImage: "gear")
                }

                Button(action: {
                    Task {
                        await sessionManager.logout()
                    }
                }) {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Flixor")
        .listStyle(.sidebar)
    }
}

#Preview {
    SidebarView(selectedItem: .constant(.home))
        .environmentObject(SessionManager.shared)
        .frame(width: 220)
}
