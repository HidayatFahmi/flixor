//
//  ImageService.swift
//  FlixorMac
//
//  Service for building image URLs from Plex and TMDB
//

import Foundation

@MainActor
class ImageService {
    static let shared = ImageService()

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - Plex Images

    func plexImageURL(path: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int? = nil) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }

        var components = URLComponents(string: apiClient.baseURL.absoluteString)
        components?.path = "/api/image/plex"

        var queryItems = [URLQueryItem(name: "path", value: path)]

        if let width = width {
            queryItems.append(URLQueryItem(name: "w", value: String(width)))
        }
        if let height = height {
            queryItems.append(URLQueryItem(name: "h", value: String(height)))
        }
        queryItems.append(URLQueryItem(name: "f", value: format))
        if let q = quality {
            queryItems.append(URLQueryItem(name: "q", value: String(q)))
        }

        components?.queryItems = queryItems

        return components?.url
    }

    // MARK: - Generic External Proxy (TMDB)

    func proxyImageURL(url: String?, width: Int? = nil, height: Int? = nil, format: String = "webp", quality: Int = 70) -> URL? {
        guard let url = url, !url.isEmpty else { return nil }

        var components = URLComponents(string: apiClient.baseURL.absoluteString)
        components?.path = "/api/image/proxy"

        var queryItems = [URLQueryItem(name: "url", value: url)]
        if let width = width { queryItems.append(URLQueryItem(name: "w", value: String(width))) }
        if let height = height { queryItems.append(URLQueryItem(name: "h", value: String(height))) }
        queryItems.append(URLQueryItem(name: "q", value: String(quality)))
        queryItems.append(URLQueryItem(name: "f", value: format))

        components?.queryItems = queryItems
        return components?.url
    }

    // MARK: - TMDB Images

    func tmdbImageURL(path: String?, size: TMDBImageSize = .w500) -> URL? {
        guard let path = path, !path.isEmpty else { return nil }

        return URL(string: "https://image.tmdb.org/t/p/\(size.rawValue)\(path)")
    }

    // MARK: - Plex Thumb

    func thumbURL(for item: MediaItem, width: Int = 300, height: Int = 450) -> URL? {
        plexImageURL(path: item.thumb, width: width, height: height)
    }

    // MARK: - Plex Art (Backdrop)

    func artURL(for item: MediaItem, width: Int = 1920, height: Int = 1080) -> URL? {
        plexImageURL(path: item.art, width: width, height: height)
    }

    // MARK: - Continue Watching Images (Backdrop style)

    /// Returns a backdrop-style image for continue watching cards.
    /// For episodes, uses the show's backdrop (grandparentArt/grandparentThumb).
    /// For movies, uses the regular backdrop (art/thumb).
    func continueWatchingURL(for item: MediaItem, width: Int = 600, height: Int = 338) -> URL? {
        // For episodes, use show's backdrop (grandparent)
        if item.type == "episode" {
            // Priority: grandparentArt > grandparentThumb > art > thumb
            let path = item.grandparentArt ?? item.grandparentThumb ?? item.art ?? item.thumb
            if let p = path, p.hasPrefix("http") {
                return proxyImageURL(url: p, width: width, height: height)
            }
            return plexImageURL(path: path, width: width, height: height, quality: 70)
        }

        // For movies/shows, use regular backdrop
        // Priority: art > thumb
        let path = item.art ?? item.thumb
        if let p = path, p.hasPrefix("http") {
            return proxyImageURL(url: p, width: width, height: height)
        }
        return plexImageURL(path: path, width: width, height: height, quality: 70)
    }
}

// MARK: - TMDB Image Sizes

enum TMDBImageSize: String {
    case w92
    case w154
    case w185
    case w342
    case w500
    case w780
    case original
}

// MARK: - Media Item Model (will be expanded later)

struct MediaItem: Identifiable, Codable {
    let id: String // ratingKey
    let title: String
    let type: String // movie, show, episode
    let thumb: String?
    let art: String?
    let year: Int?
    let rating: Double?
    let duration: Int?
    let viewOffset: Int?
    let summary: String?

    // TV Show specific fields
    let grandparentTitle: String?
    let grandparentThumb: String?
    let grandparentArt: String?
    let parentIndex: Int?
    let index: Int?

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
    }
}
