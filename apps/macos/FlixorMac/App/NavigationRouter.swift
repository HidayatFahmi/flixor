//
//  NavigationRouter.swift
//  FlixorMac
//
//  Central router to manage NavigationStack path for value-based destinations.
//

import SwiftUI

final class NavigationRouter: ObservableObject {
    @Published var path = NavigationPath()
}

