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
