//
//  HomeViewModel.swift
//  FlixorMac
//
//  View model for home screen
//

import Foundation
import SwiftUI

// MARK: - Shared lightweight models for external providers

struct TraktIDs: Codable { let tmdb: Int?; let trakt: Int?; let imdb: String?; let tvdb: Int? }
struct TraktMedia: Codable { let title: String?; let year: Int?; let ids: TraktIDs }

@MainActor
class HomeViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?

    @Published var billboardItems: [MediaItem] = []
    @Published var continueWatchingItems: [MediaItem] = []
    @Published var onDeckItems: [MediaItem] = []
    @Published var recentlyAddedItems: [MediaItem] = []
    @Published var librarySections: [LibrarySection] = []
    @Published var extraSections: [LibrarySection] = [] // TMDB/Trakt/Watchlist/Genres

    @Published var currentBillboardIndex = 0
    @Published var pendingAction: HomeAction?

    private let apiClient = APIClient.shared
    private var billboardTimer: Timer?
    private var loadTask: Task<Void, Never>?

    // MARK: - Load Data

    func loadHomeScreen() async {
        // Guard against duplicate loads
        if isLoading || loadTask != nil {
            print("⚠️ [Home] Already loading, skipping duplicate request")
            return
        }
        loadTask = Task {} // mark in-progress

        print("🏠 [Home] Starting home screen load...")
        isLoading = true
        error = nil

        // Fire-and-forget each section; update UI as each finishes
        Task { @MainActor in
            do {
                let data = try await self.fetchContinueWatching()
                self.continueWatchingItems = data
                if self.billboardItems.isEmpty, !data.isEmpty {
                    self.billboardItems = self.normalizeForHero(Array(data.prefix(5)))
                    self.startBillboardRotation()
                }
            } catch { print("⚠️ [Home] Continue Watching failed: \(error)") }
            self.isLoading = false // allow skeleton to disappear as soon as first section arrives
        }

        Task { @MainActor in
            do {
                let data = try await self.fetchOnDeck()
                self.onDeckItems = data
                if self.billboardItems.isEmpty, !data.isEmpty {
                    self.billboardItems = self.normalizeForHero(Array(data.prefix(5)))
                    self.startBillboardRotation()
                }
            } catch { print("⚠️ [Home] On Deck failed: \(error)") }
        }

        Task { @MainActor in
            do {
                let data = try await self.fetchRecentlyAdded()
                self.recentlyAddedItems = data
                if self.billboardItems.isEmpty, !data.isEmpty {
                    self.billboardItems = self.normalizeForHero(Array(data.prefix(5)))
                    self.startBillboardRotation()
                }
            } catch { print("⚠️ [Home] Recently Added failed: \(error)") }
        }

        Task { @MainActor in
            do {
                let libs = try await self.fetchLibrarySections()
                self.librarySections = libs
            } catch { print("⚠️ [Home] Libraries failed: \(error)") }
        }

        // Load additional content sections (TMDB/Trakt/Genres/Watchlist) without blocking
        Task { @MainActor in
            await self.loadAdditionalRows()
        }

        loadTask = nil
    }

    // MARK: - Refresh

    func refresh() async {
        await loadHomeScreen()
    }

    // MARK: - Additional Sections

    private func loadAdditionalRows() async {
        // Gather
        var all: [String: LibrarySection] = [:]
        var genres: [LibrarySection] = []
        var trakt: [String: LibrarySection] = [:]

        // TMDB: Popular on Plex / Trending Now
        do {
            let (popular, trending) = try await fetchTMDBTrendingTVSections()
            if let p = popular.first { all["Popular on Plex"] = p }
            if let t = trending.first { all["Trending Now"] = t }
        } catch { print("⚠️ [Home] TMDB trending failed: \(error)") }

        // Plex.tv Watchlist
        if let wl = await fetchPlexTvWatchlistSection() { all["Watchlist"] = wl }

        // Genres
        do { genres = try await fetchGenreSections() } catch { print("⚠️ [Home] Genre sections failed: \(error)") }

        // Trakt
        do {
            let t = try await fetchTraktSections()
            for s in t { trakt[s.title] = s }
        } catch { print("⚠️ [Home] Trakt sections failed: \(error)") }

        // Order exactly as requested
        var ordered: [LibrarySection] = []
        func push(_ title: String) { if let s = all[title] { ordered.append(s) } }
        push("Popular on Plex")
        // Continue Watching is rendered separately with its own card style
        push("Trending Now")
        push("Watchlist")

        // Specific genre labels in desired order
        let desiredGenres = [
            "TV Shows - Children",
            "Movie - Music",
            "Movies - Documentary",
            "Movies - History",
            "TV Shows - Reality",
            "Movies - Drama",
            "TV Shows - Suspense",
            "Movies - Animation",
        ]
        for label in desiredGenres {
            if let g = genres.first(where: { $0.title == label }) { ordered.append(g) }
        }

        // Trakt: Trending Movies, Trending TV Shows, Your Watchlist, Recently Watched, Recommended, Popular TV Shows
        let desiredTrakt = [
            "Trending Movies on Trakt",
            "Trending TV Shows on Trakt",
            "Your Trakt Watchlist",
            "Recently Watched",
            "Recommended for You",
            "Popular TV Shows on Trakt",
        ]
        for label in desiredTrakt { if let s = trakt[label] { ordered.append(s) } }

        await MainActor.run {
            print("✅ [Home] Extra sections prepared: \(ordered.map { $0.title }.joined(separator: ", "))")
            self.extraSections = ordered
        }
    }

    // MARK: - Helpers

    private func normalizeForHero(_ items: [MediaItem]) -> [MediaItem] {
        return items.map { m in
            if m.id.hasPrefix("plex:") || m.id.hasPrefix("tmdb:") { return m }
            return MediaItem(
                id: "plex:\(m.id)",
                title: m.title,
                type: m.type,
                thumb: m.thumb,
                art: m.art,
                year: m.year,
                rating: m.rating,
                duration: m.duration,
                viewOffset: m.viewOffset,
                summary: m.summary,
                grandparentTitle: m.grandparentTitle,
                grandparentThumb: m.grandparentThumb,
                grandparentArt: m.grandparentArt,
                parentIndex: m.parentIndex,
                index: m.index,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
            )
        }
    }

    // MARK: - TMDB Trending (TV)

    private func fetchTMDBTrendingTVSections() async throws -> ([LibrarySection], [LibrarySection]) {
        struct TMDBTrendingResponse: Codable { let results: [TMDBTitle] }
        struct TMDBTitle: Codable {
            let id: Int
            let name: String?
            let title: String?
            let backdrop_path: String?
            let poster_path: String?
        }

        print("📦 [Home] Fetching TMDB trending TV (week)...")
        let res: TMDBTrendingResponse = try await apiClient.get("/api/tmdb/trending/tv/week")
        let items = res.results.prefix(16)
        var mapped: [MediaItem] = []
        for r in items {
            let title = r.name ?? r.title ?? ""
            let art = ImageService.shared.tmdbImageURL(path: r.backdrop_path, size: .original)?.absoluteString
            let thumb = ImageService.shared.tmdbImageURL(path: r.poster_path, size: .w500)?.absoluteString
            let m = MediaItem(
                id: "tmdb:tv:\(r.id)",
                title: title,
                type: "show",
                thumb: thumb,
                art: art,
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
            )
            mapped.append(m)
        }
        let first = Array(mapped.prefix(8))
        let second = Array(mapped.dropFirst(8).prefix(8))
        let popular = LibrarySection(
            id: "tmdb-popular",
            title: "Popular on Plex",
            items: first,
            totalCount: first.count,
            libraryKey: nil,
            browseContext: .tmdb(kind: .trending, media: .tv, id: nil, displayTitle: "Popular on Plex")
        )
        let trending = LibrarySection(
            id: "tmdb-trending",
            title: "Trending Now",
            items: second,
            totalCount: second.count,
            libraryKey: nil,
            browseContext: .tmdb(kind: .trending, media: .tv, id: nil, displayTitle: "Trending Now")
        )
        return ([popular], [trending])
    }

    // MARK: - Plex.tv Watchlist

    private func fetchPlexTvWatchlistSection() async -> LibrarySection? {
        struct PlexContainer: Codable { let MediaContainer: PlexMC }
        struct PlexMC: Codable { let Metadata: [MediaItemFull]? }
        do {
            print("📦 [Home] Fetching Plex.tv watchlist...")
            let container: PlexContainer = try await apiClient.get("/api/plextv/watchlist")
            let meta = container.MediaContainer.Metadata ?? []

            var items: [MediaItem] = []
            for m in meta.prefix(20) {
                // Use backend-enriched tmdbGuid if available, otherwise use original ID
                var outId = m.id
                if let tmdbGuid = m.tmdbGuid {
                    // Backend already formatted as "tmdb:movie:123" or "tmdb:tv:456"
                    outId = tmdbGuid
                    print("✅ [Home] Using backend-enriched TMDB ID for \(m.title): \(tmdbGuid)")
                } else {
                    print("⚠️ [Home] No TMDB ID available for \(m.title), using original ID: \(outId)")
                }

                let item = MediaItem(
                    id: outId,
                    title: m.title,
                    type: (m.type == "movie") ? "movie" : (m.type == "show" ? "show" : m.type),
                    thumb: m.thumb,
                    art: m.art,
                    year: m.year,
                    rating: m.rating,
                    duration: m.duration,
                    viewOffset: m.viewOffset,
                    summary: m.summary,
                    grandparentTitle: m.grandparentTitle,
                    grandparentThumb: m.grandparentThumb,
                    grandparentArt: m.grandparentArt,
                    parentIndex: m.parentIndex,
                    index: m.index,
                    parentRatingKey: m.parentRatingKey,
                    parentTitle: m.parentTitle,
                    leafCount: m.leafCount,
                    viewedLeafCount: m.viewedLeafCount
                )
                items.append(item)
            }

            if items.isEmpty { return nil }
            return LibrarySection(
                id: "plextv-watchlist",
                title: "Watchlist",
                items: Array(items.prefix(12)),
                totalCount: items.count,
                libraryKey: nil,
                browseContext: .plexWatchlist
            )
        } catch {
            print("⚠️ [Home] Plex.tv watchlist failed: \(error)")
            return nil
        }
    }

    private func extractTMDBId(from guid: String) -> String? {
        // Extract digits from tmdb://... or themoviedb://...
        let prefixes = ["tmdb://", "themoviedb://"]
        for p in prefixes {
            if let range = guid.range(of: p) {
                let tail = String(guid[range.upperBound...])
                let digits = String(tail.filter { $0.isNumber })
                if digits.count >= 3 { return digits }
            }
        }
        return nil
    }

    // MARK: - Plex Genre Sections

    private func fetchGenreSections() async throws -> [LibrarySection] {
        struct Library: Codable { let key: String; let title: String; let type: String }
        struct DirContainer: Codable { let MediaContainer: DirMC }
        struct DirMC: Codable { let Directory: [DirEntry]? }
        struct DirTop: Codable { let Directory: [DirEntry]? } // some endpoints return Directory at top-level
        struct DirEntry: Codable { let key: String; let title: String; let fastKey: String? }
        struct MetaResponse: Codable {
            let MediaContainer: MetaMC?
            let Metadata: [MediaItemFull]?
        }
        struct MetaMC: Codable { let Metadata: [MediaItemFull]? }

        let genreRows: [(label: String, type: String, genre: String)] = [
            ("TV Shows - Children", "show", "Children"),
            ("Movie - Music", "movie", "Music"),
            ("Movies - Documentary", "movie", "Documentary"),
            ("Movies - History", "movie", "History"),
            ("TV Shows - Reality", "show", "Reality"),
            ("Movies - Drama", "movie", "Drama"),
            ("TV Shows - Suspense", "show", "Suspense"),
            ("Movies - Animation", "movie", "Animation"),
        ]

        print("📦 [Home] Fetching libraries for genre rows...")
        let libraries: [Library] = try await apiClient.get("/api/plex/libraries")
        let movieLib = libraries.first { $0.type == "movie" }
        let showLib = libraries.first { $0.type == "show" }

        var out: [LibrarySection] = []
        for spec in genreRows {
            let lib = (spec.type == "movie") ? movieLib : showLib
            guard let libKey = lib?.key else { continue }
            do {
                // Try top-level Directory first, then MediaContainer
                if let top: DirTop = try? await apiClient.get("/api/plex/library/\(libKey)/genre"),
                   let dir = top.Directory?.first(where: { $0.title.lowercased() == spec.genre.lowercased() }) {
                    let target = normalizedGenreRequest(dir.fastKey, libKey: libKey, rawKey: dir.key)
                    let combinedPath = Self.browsePath(path: target.path, queryItems: target.queryItems)
                    let meta: MetaResponse = try await apiClient.get("/api/plex/dir\(target.path)", queryItems: target.queryItems)
                    let items = (meta.MediaContainer?.Metadata ?? meta.Metadata ?? []).map { $0.toMediaItem() }
                    if !items.isEmpty {
                        out.append(LibrarySection(
                            id: "genre-\(spec.genre.lowercased())",
                            title: spec.label,
                            items: Array(items.prefix(12)),
                            totalCount: items.count,
                            libraryKey: libKey,
                            browseContext: .plexDirectory(path: combinedPath, title: spec.label)
                        ))
                    }
                    continue
                }
                let dirs: DirContainer = try await apiClient.get("/api/plex/library/\(libKey)/genre")
                guard let dir = dirs.MediaContainer.Directory?.first(where: { $0.title.lowercased() == spec.genre.lowercased() }) else { continue }
                let target = normalizedGenreRequest(dir.fastKey, libKey: libKey, rawKey: dir.key)
                let combinedPath = Self.browsePath(path: target.path, queryItems: target.queryItems)
                let meta: MetaResponse = try await apiClient.get("/api/plex/dir\(target.path)", queryItems: target.queryItems)
                let items = (meta.MediaContainer?.Metadata ?? meta.Metadata ?? []).map { $0.toMediaItem() }
                if !items.isEmpty {
                    out.append(LibrarySection(
                        id: "genre-\(spec.genre.lowercased())",
                        title: spec.label,
                        items: Array(items.prefix(12)),
                        totalCount: items.count,
                        libraryKey: libKey,
                        browseContext: .plexDirectory(path: combinedPath, title: spec.label)
                    ))
                }
            } catch {
                print("⚠️ [Home] Genre fetch failed for \(spec.label): \(error)")
            }
        }
        return out
    }

    private func normalizedGenreRequest(_ fastKey: String?, libKey: String, rawKey: String) -> (path: String, queryItems: [URLQueryItem]?) {
        var key = fastKey ?? "/library/sections/\(libKey)/all?genre=\(rawKey)"
        if !key.hasPrefix("/") { key = "/\(key)" }

        if let questionIndex = key.firstIndex(of: "?") {
            let path = String(key[..<questionIndex])
            let query = String(key[key.index(after: questionIndex)...])
            let components = query.split(separator: "&").map { pair -> URLQueryItem in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                let name = parts.first ?? ""
                let value = parts.count > 1 ? parts[1] : nil
                return URLQueryItem(name: name, value: value)
            }
            return (path, components)
        }
        return (key, nil)
    }

    private static func browsePath(path: String, queryItems: [URLQueryItem]?) -> String {
        guard let queryItems, !queryItems.isEmpty else { return path }
        let query = queryItems.compactMap { item -> String? in
            guard let value = item.value else { return item.name }
            return "\(item.name)=\(value)"
        }.joined(separator: "&")
        return "\(path)?\(query)"
    }

    // MARK: - Trakt Sections

    private func fetchTraktSections() async throws -> [LibrarySection] {
        var sections: [LibrarySection] = []

        // Trending Movies (public)
        do {
            let items = try await fetchTraktTrending(media: "movies")
            if !items.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-trending-movies",
                    title: "Trending Movies on Trakt",
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .trendingMovies)
                ))
            }
        } catch { print("⚠️ [Home] Trakt trending movies failed: \(error)") }

        // Trending TV Shows (public)
        do {
            let items = try await fetchTraktTrending(media: "shows")
            if !items.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-trending-shows",
                    title: "Trending TV Shows on Trakt",
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .trendingShows)
                ))
            }
        } catch { print("⚠️ [Home] Trakt trending shows failed: \(error)") }

        // Your Trakt Watchlist (auth)
        if let wl = try? await fetchTraktWatchlist() {
            if !wl.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-watchlist",
                    title: "Your Trakt Watchlist",
                    items: wl,
                    totalCount: wl.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .watchlist)
                ))
            }
        }

        // Recently Watched (auth)
        if let hist = try? await fetchTraktHistory() {
            if !hist.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-history",
                    title: "Recently Watched",
                    items: hist,
                    totalCount: hist.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .history)
                ))
            }
        }

        // Recommended for You (auth)
        if let rec = try? await fetchTraktRecommendations() {
            if !rec.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-recs",
                    title: "Recommended for You",
                    items: rec,
                    totalCount: rec.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .recommendations)
                ))
            }
        }

        // Popular TV Shows on Trakt (public)
        do {
            let items = try await fetchTraktPopular(media: "shows")
            if !items.isEmpty {
                sections.append(LibrarySection(
                    id: "trakt-popular-shows",
                    title: "Popular TV Shows on Trakt",
                    items: items,
                    totalCount: items.count,
                    libraryKey: nil,
                    browseContext: .trakt(kind: .popularShows)
                ))
            }
        } catch { print("⚠️ [Home] Trakt popular shows failed: \(error)") }

        return sections
    }

    // Helpers: Trakt mappers
    private func fetchTraktTrending(media: String) async throws -> [MediaItem] {
        struct TraktTrendingItem: Codable { let watchers: Int?; let movie: TraktMedia?; let show: TraktMedia? }
        let arr: [TraktTrendingItem] = try await apiClient.get("/api/trakt/trending/\(media)")
        let mediaType = (media == "movies") ? "movie" : "tv"
        let limited = Array(arr.prefix(12))
        let list: [TraktMedia] = limited.compactMap { $0.movie ?? $0.show }
        return await mapTraktMediaListToMediaItems(list, mediaType: mediaType)
    }

    private func fetchTraktPopular(media: String) async throws -> [MediaItem] {
        
        let arr: [TraktMedia] = try await apiClient.get("/api/trakt/popular/\(media)")
        let mediaType = (media == "movies") ? "movie" : "tv"
        let limited = Array(arr.prefix(12))
        return await mapTraktMediaListToMediaItems(limited, mediaType: mediaType)
    }

    private func fetchTraktWatchlist() async throws -> [MediaItem]? {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        do {
            let arr: [TraktItem] = try await apiClient.get("/api/trakt/users/me/watchlist")
            let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
            let items = await mapTraktMediaListToMediaItems(Array(mediaList.prefix(12)), mediaType: nil)
            return items
        } catch {
            // likely 401 if not authenticated
            return nil
        }
    }

    private func fetchTraktHistory() async throws -> [MediaItem]? {
        struct TraktItem: Codable { let movie: TraktMedia?; let show: TraktMedia? }
        do {
            let arr: [TraktItem] = try await apiClient.get("/api/trakt/users/me/history")
            let mediaList: [TraktMedia] = arr.compactMap { $0.movie ?? $0.show }
            let items = await mapTraktMediaListToMediaItems(Array(mediaList.prefix(12)), mediaType: nil)
            return items
        } catch { return nil }
    }

    private func fetchTraktRecommendations() async throws -> [MediaItem]? {
        
        do {
            let arr: [TraktMedia] = try await apiClient.get("/api/trakt/recommendations/movies")
            let items = await mapTraktMediaListToMediaItems(Array(arr.prefix(12)), mediaType: "movie")
            return items
        } catch { return nil }
    }

    private func mapTraktMediaListToMediaItems(_ list: [TraktMedia], mediaType: String?) async -> [MediaItem] {
        var out: [MediaItem] = []
        await withTaskGroup(of: MediaItem?.self) { group in
            for media in list {
                group.addTask {
                    guard let tmdb = media.ids.tmdb else { return nil }
                    let inferredType: String = mediaType ?? "movie"
                    let title = media.title ?? ""
                    do {
                        let backdrop = try await self.fetchTMDBBackdrop(mediaType: inferredType, id: tmdb)
                        let m = MediaItem(
                            id: "tmdb:\(inferredType):\(tmdb)",
                            title: title,
                            type: inferredType == "movie" ? "movie" : "show",
                            thumb: nil,
                            art: backdrop,
                            year: media.year,
                            rating: nil,
                            duration: nil,
                            viewOffset: nil,
                            summary: nil,
                            grandparentTitle: nil,
                            grandparentThumb: nil,
                            grandparentArt: nil,
                            parentIndex: nil,
                            index: nil,
                parentRatingKey: nil,
                parentTitle: nil,
                leafCount: nil,
                viewedLeafCount: nil
                        )
                        return m
                    } catch { return nil }
                }
            }
            for await maybe in group { if let m = maybe { out.append(m) } }
        }
        return out
    }

    private func fetchTMDBBackdrop(mediaType: String, id: Int) async throws -> String? {
        struct TMDBTitle: Codable { let backdrop_path: String? }
        let path = "/api/tmdb/\(mediaType)/\(id)"
        let detail: TMDBTitle = try await apiClient.get(path)
        if let p = detail.backdrop_path {
            return ImageService.shared.tmdbImageURL(path: p, size: .original)?.absoluteString
        }
        return nil
    }

    // MARK: - Fetch Methods

    private func fetchOnDeck() async throws -> [MediaItem] {
        print("📦 [Home] Fetching on deck items...")
        let items: [MediaItemFull] = try await apiClient.get("/api/plex/ondeck")
        print("✅ [Home] Received \(items.count) on deck items")
        return items.map { $0.toMediaItem() }
    }

    private func fetchContinueWatching() async throws -> [MediaItem] {
        print("📦 [Home] Fetching continue watching items...")
        let items: [MediaItemFull] = try await apiClient.get("/api/plex/continue")
        print("✅ [Home] Received \(items.count) continue watching items")

        // Enrich with TMDB backdrop URLs before returning
        let baseItems = items.map { $0.toMediaItem() }
        return await enrichWithTMDBBackdrops(baseItems)
    }

    private func enrichWithTMDBBackdrops(_ items: [MediaItem]) async -> [MediaItem] {
        print("🎨 [Home] Enriching \(items.count) items with TMDB backdrops...")

        return await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    // Try to fetch TMDB backdrop
                    if let backdropURL = try? await self.resolveTMDBBackdropForItem(item) {
                        // Create new MediaItem with TMDB backdrop
                        let enriched = MediaItem(
                            id: item.id,
                            title: item.title,
                            type: item.type,
                            thumb: item.thumb,
                            art: backdropURL, // Replace with TMDB backdrop
                            year: item.year,
                            rating: item.rating,
                            duration: item.duration,
                            viewOffset: item.viewOffset,
                            summary: item.summary,
                            grandparentTitle: item.grandparentTitle,
                            grandparentThumb: item.grandparentThumb,
                            grandparentArt: item.grandparentArt,
                            parentIndex: item.parentIndex,
                            index: item.index,
                            parentRatingKey: nil,
                            parentTitle: nil,
                            leafCount: nil,
                            viewedLeafCount: nil
                        )
                        return (index, enriched)
                    }
                    // Return original item if TMDB fetch fails
                    return (index, item)
                }
            }

            // Collect results and maintain order
            var enrichedItems: [(Int, MediaItem)] = []
            for await result in group {
                enrichedItems.append(result)
            }

            // Sort by original index and return just the items
            let sorted = enrichedItems.sorted { $0.0 < $1.0 }.map { $0.1 }
            print("✅ [Home] Enriched \(sorted.count) items with TMDB backdrops")
            return sorted
        }
    }

    private func resolveTMDBBackdropForItem(_ item: MediaItem) async throws -> String? {
        print("🔍 [Home] Resolving TMDB backdrop for: \(item.title) (id: \(item.id), type: \(item.type))")

        // Handle plain numeric IDs (assume they're Plex rating keys)
        let normalizedId: String
        if item.id.hasPrefix("plex:") || item.id.hasPrefix("tmdb:") {
            normalizedId = item.id
        } else {
            // Plain numeric ID - treat as Plex rating key
            normalizedId = "plex:\(item.id)"
        }

        if normalizedId.hasPrefix("tmdb:") {
            let parts = normalizedId.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                let url = try await fetchTMDBBestBackdropURLString(mediaType: media, id: id)
                print("✅ [Home] TMDB backdrop resolved for \(item.title): \(url ?? "nil")")
                return url
            }
        }

        if normalizedId.hasPrefix("plex:") {
            let rk = String(normalizedId.dropFirst(5))

            // Use MediaItemFull which has all the metadata we need
            do {
                let fullItem: MediaItemFull = try await apiClient.get("/api/plex/metadata/\(rk)")

                // For TV episodes, fetch the parent series metadata instead
                if fullItem.type == "episode", let grandparentRatingKey = fullItem.grandparentRatingKey {
                    print("📺 [Home] Episode detected, fetching parent series metadata for \(item.title)")
                    let seriesItem: MediaItemFull = try await apiClient.get("/api/plex/metadata/\(grandparentRatingKey)")

                    // Extract TMDB ID from series Guid array
                    if let guidArray = seriesItem.Guid {
                        for guidEntry in guidArray {
                            if guidEntry.id.contains("tmdb://") || guidEntry.id.contains("themoviedb://") {
                                if let tmdbId = extractTMDBId(from: guidEntry.id) {
                                    let url = try await fetchTMDBBestBackdropURLString(mediaType: "tv", id: tmdbId)
                                    print("✅ [Home] TMDB backdrop resolved for \(item.title) from series Guid array: \(url ?? "nil")")
                                    return url
                                }
                            }
                        }
                    }

                    // Fallback to series guid string
                    if let guid = seriesItem.guid {
                        if let tmdbId = extractTMDBId(from: guid) {
                            let url = try await fetchTMDBBestBackdropURLString(mediaType: "tv", id: tmdbId)
                            print("✅ [Home] TMDB backdrop resolved for \(item.title) from series guid string: \(url ?? "nil")")
                            return url
                        }
                    }
                    print("⚠️ [Home] No TMDB ID found in series metadata for \(item.title)")
                    return nil
                }

                // For movies and shows, extract TMDB ID from Guid array (prioritize over guid string)
                if let guidArray = fullItem.Guid {
                    for guidEntry in guidArray {
                        if guidEntry.id.contains("tmdb://") || guidEntry.id.contains("themoviedb://") {
                            if let tmdbId = extractTMDBId(from: guidEntry.id) {
                                let mediaType = (fullItem.type == "movie") ? "movie" : "tv"
                                let url = try await fetchTMDBBestBackdropURLString(mediaType: mediaType, id: tmdbId)
                                print("✅ [Home] TMDB backdrop resolved for \(item.title) from Guid array: \(url ?? "nil")")
                                return url
                            }
                        }
                    }
                }

                // Fallback to guid string field if Guid array not present
                if let guid = fullItem.guid {
                    if let tmdbId = extractTMDBId(from: guid) {
                        let mediaType = (fullItem.type == "movie") ? "movie" : "tv"
                        let url = try await fetchTMDBBestBackdropURLString(mediaType: mediaType, id: tmdbId)
                        print("✅ [Home] TMDB backdrop resolved for \(item.title) from guid string: \(url ?? "nil")")
                        return url
                    }
                }
                print("⚠️ [Home] No TMDB ID found in Guid array or guid string for \(item.title)")
            } catch {
                print("❌ [Home] Failed to fetch metadata for \(item.title): \(error)")
            }
        }

        return nil
    }

    private func fetchTMDBBestBackdropURLString(mediaType: String, id: String) async throws -> String? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }

        let imgs: TMDBImages = try await apiClient.get("/api/tmdb/\(mediaType)/\(id)/images")
        let backs = imgs.backdrops ?? []
        if backs.isEmpty { return nil }

        let pick: ([TMDBImage]) -> TMDBImage? = { arr in
            return arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }

        // Priority: en > hi > any non-null language > null (no text)
        let en = pick(backs.filter { $0.iso_639_1 == "en" })
        let hi = pick(backs.filter { $0.iso_639_1 == "hi" })
        let withLang = pick(backs.filter { $0.iso_639_1 != nil && $0.iso_639_1 != "en" && $0.iso_639_1 != "hi" })
        let nul = pick(backs.filter { $0.iso_639_1 == nil })
        let sel = en ?? hi ?? withLang ?? nul

        guard let path = sel?.file_path else { return nil }
        let full = "https://image.tmdb.org/t/p/original\(path)"
        return ImageService.shared.proxyImageURL(url: full, width: 840, height: 420)?.absoluteString
    }

    private func fetchRecentlyAdded() async throws -> [MediaItem] {
        print("📦 [Home] Fetching recently added items...")
        let items: [MediaItemFull] = try await apiClient.get("/api/plex/recent")
        print("✅ [Home] Received \(items.count) recently added items")
        return items.map { $0.toMediaItem() }
    }

    private func fetchLibrarySections() async throws -> [LibrarySection] {
        struct Library: Codable {
            let key: String
            let title: String
            let type: String
        }

        print("📦 [Home] Fetching libraries...")
        let libraries: [Library] = try await apiClient.get("/api/plex/libraries")
        print("✅ [Home] Received \(libraries.count) libraries")

        // Fetch items for each library (limit to first 20)
        var sections: [LibrarySection] = []

        for library in libraries {
            do {
                print("📦 [Home] Fetching items for library: \(library.title)")
                let items: [MediaItemFull] = try await apiClient.get(
                    "/api/plex/library/\(library.key)/all",
                    queryItems: [
                        URLQueryItem(name: "offset", value: "0"),
                        URLQueryItem(name: "limit", value: "20")
                    ]
                )

                if !items.isEmpty {
                    print("✅ [Home] Received \(items.count) items for \(library.title)")
                    sections.append(LibrarySection(
                        id: library.key,
                        title: library.title,
                        items: items.map { $0.toMediaItem() },
                        totalCount: items.count,
                        libraryKey: library.key,
                        browseContext: .plexLibrary(key: library.key, title: library.title)
                    ))
                }
            } catch {
                print("⚠️ [Home] Failed to load library \(library.title): \(error)")
                // Continue with other libraries
            }
        }

        return sections
    }

    // MARK: - Billboard Rotation

    private func startBillboardRotation() {
        guard !billboardItems.isEmpty else { return }

        billboardTimer?.invalidate()
        billboardTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                withAnimation {
                    self.currentBillboardIndex = (self.currentBillboardIndex + 1) % self.billboardItems.count
                }
            }
        }
    }

    func stopBillboardRotation() {
        billboardTimer?.invalidate()
        billboardTimer = nil
    }

    // MARK: - Navigation

    func playItem(_ item: MediaItem) {
        pendingAction = .play(item)
    }

    func showItemDetails(_ item: MediaItem) {
        pendingAction = .details(item)
    }

    func toggleMyList(_ item: MediaItem) {
        // TODO: Add/remove from watchlist
        print("Toggle My List: \(item.title)")
    }

    // MARK: - Cleanup

    deinit {
        billboardTimer?.invalidate()
    }
}

// MARK: - Navigation Actions

enum HomeAction {
    case play(MediaItem)
    case details(MediaItem)
}

extension HomeAction: Equatable {
    static func == (lhs: HomeAction, rhs: HomeAction) -> Bool {
        switch (lhs, rhs) {
        case (.play(let a), .play(let b)): return a.id == b.id
        case (.details(let a), .details(let b)): return a.id == b.id
        default: return false
        }
    }
}
