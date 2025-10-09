//
//  WatchlistController.swift
//  FlixorMac
//
//  Shared store for watchlist state so buttons and views stay in sync.
//

import Foundation
import SwiftUI

extension Notification.Name {
    static let watchlistDidChange = Notification.Name("watchlistDidChange")
}

@MainActor
final class WatchlistController: ObservableObject {
    @Published private(set) var ids: Set<String> = []

    func synchronize(with items: [MyListViewModel.WatchlistItem]) {
        ids = Set(items.map { normalize($0.id) })
    }

    func contains(_ id: String) -> Bool {
        ids.contains(normalize(id))
    }

    func registerAdd(id: String) {
        ids.insert(normalize(id))
        NotificationCenter.default.post(name: .watchlistDidChange, object: nil)
    }

    func registerRemove(id: String) {
        ids.remove(normalize(id))
        NotificationCenter.default.post(name: .watchlistDidChange, object: nil)
    }

    private func normalize(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
