//
//  HomeScreenData.swift
//  FlixorMac
//
//  Models for home screen data
//

import Foundation

struct HomeScreenData {
    let billboard: [MediaItem]
    let continueWatching: [MediaItem]
    let onDeck: [MediaItem]
    let recentlyAdded: [MediaItem]
    let librarySections: [LibrarySection]
}

struct LibrarySection: Identifiable {
    let id: String
    let title: String
    let items: [MediaItem]
    let totalCount: Int
    let libraryKey: String?
}

// Extended MediaItem with additional properties
extension MediaItem {
    var episodeLabel: String? {
        guard let grandparentTitle = grandparentTitle else { return nil }

        var label = grandparentTitle
        if let seasonIndex = parentIndex, let episodeIndex = index {
            label += " • S\(seasonIndex):E\(episodeIndex)"
        }
        return label
    }

    var displayTitle: String {
        if let grandparent = grandparentTitle {
            return "\(grandparent) • \(title)"
        }
        return title
    }

    var progressText: String? {
        guard let duration = duration, duration > 0,
              let viewOffset = viewOffset, viewOffset > 0 else {
            return nil
        }

        let remaining = duration - viewOffset
        let minutes = remaining / 60000

        if minutes < 60 {
            return "\(minutes) min left"
        } else {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h \(mins)m left"
        }
    }
}

// Complete MediaItem structure with all fields
struct MediaItemFull: Identifiable, Codable {
    let id: String // ratingKey
    let title: String
    let type: String
    let thumb: String?
    let art: String?
    let year: Int?
    let rating: Double?
    let duration: Int?
    let viewOffset: Int?
    let summary: String?

    // TV Show specific
    let grandparentTitle: String?
    let grandparentThumb: String?
    let grandparentArt: String?
    let parentIndex: Int?
    let index: Int?

    // Additional metadata
    let addedAt: Int?
    let lastViewedAt: Int?
    let contentRating: String?
    let contentRatingAge: Int?
    let studio: String?
    let tagline: String?
    let key: String?
    let guid: String?
    let slug: String?

    // Library metadata
    let allowSync: Bool?
    let librarySectionID: Int?
    let librarySectionTitle: String?
    let librarySectionUUID: String?

    enum CodingKeys: String, CodingKey {
        case id = "ratingKey"
        case title
        case type
        case thumb
        case art
        case year
        case rating
        case duration
        case viewOffset
        case summary
        case grandparentTitle
        case grandparentThumb
        case grandparentArt
        case parentIndex
        case index
        case addedAt
        case lastViewedAt
        case contentRating
        case contentRatingAge
        case studio
        case tagline
        case key
        case guid
        case slug
        case allowSync
        case librarySectionID
        case librarySectionTitle
        case librarySectionUUID
    }

    // Convert to MediaItem
    func toMediaItem() -> MediaItem {
        MediaItem(
            id: id,
            title: title,
            type: type,
            thumb: thumb,
            art: art,
            year: year,
            rating: rating,
            duration: duration,
            viewOffset: viewOffset,
            summary: summary,
            grandparentTitle: grandparentTitle,
            grandparentThumb: grandparentThumb,
            grandparentArt: grandparentArt,
            parentIndex: parentIndex,
            index: index
        )
    }
}

// API Response structures
struct OnDeckResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct ContinueWatchingResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct RecentlyAddedResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct LibraryResponse: Codable {
    let size: Int
    let items: [MediaItemFull]

    enum CodingKeys: String, CodingKey {
        case size
        case items = "Metadata"
    }
}

struct LibrariesResponse: Codable {
    let libraries: [Library]

    struct Library: Codable, Identifiable {
        let key: String
        let type: String
        let title: String
        let agent: String?
        let scanner: String?
        let language: String?
        let uuid: String?

        var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key
            case type
            case title
            case agent
            case scanner
            case language
            case uuid
        }
    }

    enum CodingKeys: String, CodingKey {
        case libraries = "Directory"
    }
}
