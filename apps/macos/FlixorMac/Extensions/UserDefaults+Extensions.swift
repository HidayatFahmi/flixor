//
//  UserDefaults+Extensions.swift
//  FlixorMac
//
//  UserDefaults extensions for app preferences
//

import Foundation

extension UserDefaults {
    // MARK: - Keys

    private enum Keys {
        static let backendBaseURL = "backendBaseURL"
        static let defaultQuality = "defaultQuality"
        static let autoPlayNext = "autoPlayNext"
        static let skipIntroAutomatically = "skipIntroAutomatically"
        static let skipCreditsAutomatically = "skipCreditsAutomatically"
        static let traktAutoSyncWatched = "traktAutoSyncWatched"
        static let traktSyncRatings = "traktSyncRatings"
        static let traktSyncWatchlist = "traktSyncWatchlist"
    }

    // MARK: - Backend URL

    var backendBaseURL: String {
        get { string(forKey: Keys.backendBaseURL) ?? "http://localhost:3001" }
        set { set(newValue, forKey: Keys.backendBaseURL) }
    }

    // MARK: - Playback Preferences

    var defaultQuality: Int {
        get { integer(forKey: Keys.defaultQuality) != 0 ? integer(forKey: Keys.defaultQuality) : 12000 }
        set { set(newValue, forKey: Keys.defaultQuality) }
    }

    var autoPlayNext: Bool {
        get { bool(forKey: Keys.autoPlayNext) }
        set { set(newValue, forKey: Keys.autoPlayNext) }
    }

    var skipIntroAutomatically: Bool {
        get { bool(forKey: Keys.skipIntroAutomatically) }
        set { set(newValue, forKey: Keys.skipIntroAutomatically) }
    }

    var skipCreditsAutomatically: Bool {
        get { bool(forKey: Keys.skipCreditsAutomatically) }
        set { set(newValue, forKey: Keys.skipCreditsAutomatically) }
    }
}

extension UserDefaults {
    var traktAutoSyncWatched: Bool {
        get { object(forKey: Keys.traktAutoSyncWatched) as? Bool ?? true }
        set { set(newValue, forKey: Keys.traktAutoSyncWatched) }
    }

    var traktSyncRatings: Bool {
        get { object(forKey: Keys.traktSyncRatings) as? Bool ?? true }
        set { set(newValue, forKey: Keys.traktSyncRatings) }
    }

    var traktSyncWatchlist: Bool {
        get { object(forKey: Keys.traktSyncWatchlist) as? Bool ?? true }
        set { set(newValue, forKey: Keys.traktSyncWatchlist) }
    }
}
