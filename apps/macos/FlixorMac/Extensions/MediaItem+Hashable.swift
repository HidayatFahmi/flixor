//
//  MediaItem+Hashable.swift
//  FlixorMac
//
//  Allow MediaItem to be used with NavigationDestination by hashing on id.
//

import Foundation

extension MediaItem: Hashable {
    public static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

