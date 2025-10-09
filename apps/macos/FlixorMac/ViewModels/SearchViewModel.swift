//
//  SearchViewModel.swift
//  FlixorMac
//
//  ViewModel for Search screen with Popular/Trending/Live results
//

import Foundation
import SwiftUI
import Combine

@MainActor
class SearchViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var query: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var popularItems: [SearchResult] = []
    @Published var trendingItems: [SearchResult] = []
    @Published var isLoading = false
    @Published var searchMode: SearchMode = .idle

    enum SearchMode {
        case idle          // Show Popular/Trending
        case searching     // Actively searching
        case results       // Showing results
    }

    struct SearchResult: Identifiable, Hashable {
        let id: String
        let title: String
        let type: MediaType
        let imageURL: URL?
        let year: String?
        let overview: String?
        let available: Bool  // true if in Plex library

        enum MediaType: String {
            case movie, tv, collection
        }
    }

    private let api = APIClient.shared
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupSearchDebouncing()
    }

    // MARK: - Setup

    private func setupSearchDebouncing() {
        // Debounce search input (300ms)
        $query
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                Task { @MainActor in
                    if newQuery.isEmpty {
                        self.searchMode = .idle
                        self.searchResults = []
                    } else {
                        self.searchMode = .searching
                        await self.performSearch(query: newQuery)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Load Initial Content

    func loadInitialContent() async {
        await withTaskGroup(of: Void.self) { group in
            // Load popular items
            group.addTask { await self.loadPopularItems() }
            // Load trending items
            group.addTask { await self.loadTrendingItems() }
        }
    }

    private func loadPopularItems() async {
        do {
            // Fetch popular movies and TV shows from TMDB
            struct PopularResponse: Codable {
                let results: [PopularItem]
            }
            struct PopularItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
            }

            async let movies: PopularResponse = api.get("/api/tmdb/movie/popular")
            async let shows: PopularResponse = api.get("/api/tmdb/tv/popular")

            let (movieResults, showResults) = try await (movies, shows)

            var popular: [SearchResult] = []

            // Add popular movies (first 6)
            for item in movieResults.results.prefix(6) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                popular.append(SearchResult(
                    id: "tmdb:movie:\(item.id)",
                    title: item.title ?? "",
                    type: .movie,
                    imageURL: imageURL,
                    year: item.release_date?.prefix(4).description,
                    overview: nil,
                    available: false
                ))
            }

            // Add popular TV shows (first 6)
            for item in showResults.results.prefix(6) {
                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                popular.append(SearchResult(
                    id: "tmdb:tv:\(item.id)",
                    title: item.name ?? "",
                    type: .tv,
                    imageURL: imageURL,
                    year: item.first_air_date?.prefix(4).description,
                    overview: nil,
                    available: false
                ))
            }

            self.popularItems = Array(popular.prefix(10))
            print("📊 [Search] Loaded \(self.popularItems.count) popular items")
        } catch {
            print("❌ [Search] Failed to load popular items: \(error)")
        }
    }

    private func loadTrendingItems() async {
        do {
            // Fetch trending content from TMDB
            struct TrendingResponse: Codable {
                let results: [TrendingItem]
            }
            struct TrendingItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let media_type: String
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
            }

            let response: TrendingResponse = try await api.get("/api/tmdb/trending/all/week")

            let trending: [SearchResult] = response.results.prefix(12).compactMap { item in
                guard item.media_type == "movie" || item.media_type == "tv" else { return nil }

                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                return SearchResult(
                    id: "tmdb:\(item.media_type):\(item.id)",
                    title: item.title ?? item.name ?? "",
                    type: item.media_type == "movie" ? .movie : .tv,
                    imageURL: imageURL,
                    year: (item.release_date ?? item.first_air_date)?.prefix(4).description,
                    overview: nil,
                    available: false
                )
            }

            self.trendingItems = trending
            print("🔥 [Search] Loaded \(self.trendingItems.count) trending items")
        } catch {
            print("❌ [Search] Failed to load trending items: \(error)")
        }
    }

    // MARK: - Search

    private func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            searchMode = .idle
            return
        }

        // Cancel previous search task
        searchTask?.cancel()

        searchTask = Task {
            isLoading = true
            defer { isLoading = false }

            print("🔍 [Search] Searching for: \(query)")

            var results: [SearchResult] = []

            // Search Plex first
            await withTaskGroup(of: [SearchResult].self) { group in
                // Search Plex movies
                group.addTask { await self.searchPlex(query: query, type: 1) }
                // Search Plex TV shows
                group.addTask { await self.searchPlex(query: query, type: 2) }

                for await plexResults in group {
                    results.append(contentsOf: plexResults)
                }
            }

            // Search TMDB as fallback
            let tmdbResults = await searchTMDB(query: query)

            // Filter out TMDB results that match Plex titles
            let filteredTMDB = tmdbResults.filter { tmdbItem in
                !results.contains { plexItem in
                    plexItem.title.lowercased() == tmdbItem.title.lowercased()
                }
            }

            results.append(contentsOf: filteredTMDB)

            guard !Task.isCancelled else { return }

            self.searchResults = results
            self.searchMode = .results
            print("✅ [Search] Found \(results.count) results for '\(query)'")
        }
    }

    private func searchPlex(query: String, type: Int) async -> [SearchResult] {
        do {
            // type: 1 = movies, 2 = tv shows
            let response: [PlexSearchItem] = try await api.get(
                "/api/plex/search",
                queryItems: [
                    URLQueryItem(name: "query", value: query),
                    URLQueryItem(name: "type", value: String(type))
                ]
            )

            return response.prefix(10).map { item in
                let imagePath = item.art ?? item.thumb ?? item.parentThumb ?? item.grandparentThumb ?? ""
                let imageURL = ImageService.shared.plexImageURL(path: imagePath, width: 600, height: 338)

                return SearchResult(
                    id: "plex:\(item.ratingKey)",
                    title: item.title ?? "",
                    type: type == 1 ? .movie : .tv,
                    imageURL: imageURL,
                    year: item.year.map(String.init),
                    overview: item.summary,
                    available: true
                )
            }
        } catch {
            print("❌ [Search] Plex search failed (type=\(type)): \(error)")
            return []
        }
    }

    private func searchTMDB(query: String) async -> [SearchResult] {
        do {
            struct TMDBSearchResponse: Codable {
                let results: [TMDBSearchItem]
            }
            struct TMDBSearchItem: Codable {
                let id: Int
                let title: String?
                let name: String?
                let media_type: String
                let backdrop_path: String?
                let poster_path: String?
                let release_date: String?
                let first_air_date: String?
                let overview: String?
            }

            let response: TMDBSearchResponse = try await api.get(
                "/api/tmdb/search/multi",
                queryItems: [URLQueryItem(name: "query", value: query)]
            )

            return response.results.prefix(20).compactMap { item in
                guard item.media_type == "movie" || item.media_type == "tv" else { return nil }

                let imageURL = ImageService.shared.proxyImageURL(
                    url: item.backdrop_path.flatMap { "https://image.tmdb.org/t/p/w780\($0)" }
                ) ?? ImageService.shared.proxyImageURL(
                    url: item.poster_path.flatMap { "https://image.tmdb.org/t/p/w500\($0)" }
                )

                return SearchResult(
                    id: "tmdb:\(item.media_type):\(item.id)",
                    title: item.title ?? item.name ?? "",
                    type: item.media_type == "movie" ? .movie : .tv,
                    imageURL: imageURL,
                    year: (item.release_date ?? item.first_air_date)?.prefix(4).description,
                    overview: item.overview,
                    available: false
                )
            }
        } catch {
            print("❌ [Search] TMDB search failed: \(error)")
            return []
        }
    }

    // MARK: - Helper Structs

    private struct PlexSearchItem: Codable {
        let ratingKey: String
        let title: String?
        let year: Int?
        let summary: String?
        let art: String?
        let thumb: String?
        let parentThumb: String?
        let grandparentThumb: String?
    }
}
