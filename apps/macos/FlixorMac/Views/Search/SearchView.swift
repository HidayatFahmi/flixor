//
//  SearchView.swift
//  FlixorMac
//
//  Search screen with Popular/Trending and live search results
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainViewState: MainViewState

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            SearchBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Search Input Field
                    SearchInputField(query: $viewModel.query)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    // Content based on search mode
                    Group {
                        switch viewModel.searchMode {
                        case .idle:
                            IdleStateView(viewModel: viewModel, onTap: { item in
                                navigateToDetails(item: item)
                            })
                        case .searching:
                            LoadingView(message: "Searching...")
                        case .results:
                            let hasResults = !viewModel.plexResults.isEmpty ||
                                           !viewModel.tmdbMovies.isEmpty ||
                                           !viewModel.tmdbShows.isEmpty
                            if hasResults {
                                SearchResultsView(viewModel: viewModel, onTap: { item in
                                    navigateToDetails(item: item)
                                })
                            } else {
                                EmptyStateView(query: viewModel.query)
                            }
                        }
                    }
                    .padding(.top, 24)
                }
            }
        }
        .navigationTitle("")
        .task {
            if viewModel.popularItems.isEmpty && viewModel.trendingItems.isEmpty {
                await viewModel.loadInitialContent()
            }
        }
        .toast()
    }

    private func navigateToDetails(item: SearchViewModel.SearchResult) {
        let mediaItem = MediaItem(
            id: item.id,
            title: item.title,
            type: item.type.rawValue,
            thumb: item.imageURL?.absoluteString,
            art: nil,
            year: item.year.flatMap { Int($0) },
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: item.overview,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
        router.searchPath.append(DetailsNavigationItem(item: mediaItem))
    }
}

// MARK: - Search Input Field

struct SearchInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search for movies, TV shows...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)

            if !query.isEmpty {
                Button(action: {
                    query = ""
                    isFocused = true
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(isFocused ? 0.20 : 0.12), lineWidth: 1)
        )
    }
}

// MARK: - Idle State (Grid of Trending Items with Landscape Cards)

struct IdleStateView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommended TV Shows & Movies")
                .font(.title2.bold())
                .padding(.horizontal, 20)

            // Adaptive grid of trending items using landscape cards
            TrendingResultsGrid(items: viewModel.trendingItems, onTap: onTap)
        }
    }
}

// MARK: - Trending Results Grid (Landscape Cards)

struct TrendingResultsGrid: View {
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    @State private var gridHeight: CGFloat = 200

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 40 // Account for horizontal padding
            let cardWidth: CGFloat = 360
            let spacing: CGFloat = 16
            let columns = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))

            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)

            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(items) { result in
                    SearchLandscapeCard(result: result) {
                        onTap(result)
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(
                GeometryReader { contentGeometry in
                    Color.clear.preference(
                        key: TrendingGridHeightKey.self,
                        value: contentGeometry.size.height
                    )
                }
            )
            .onPreferenceChange(TrendingGridHeightKey.self) { height in
                gridHeight = height
            }
        }
        .frame(height: gridHeight)
    }
}

struct TrendingGridHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Search Landscape Card (for trending items)

struct SearchLandscapeCard: View {
    let result: SearchViewModel.SearchResult
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 0.5

            Button(action: onTap) {
                ZStack(alignment: .bottomLeading) {
                    // Backdrop image (TMDB with non-null iso_639_1)
                    Group {
                        if let url = result.imageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    SkeletonView(height: height, cornerRadius: 14)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    PlaceholderImage()
                                @unknown default:
                                    PlaceholderImage()
                                }
                            }
                        } else {
                            PlaceholderImage()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipped()

                    // Gradient overlay for text readability
                    LinearGradient(
                        colors: [
                            .black.opacity(0.0),
                            .black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Title overlay
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let year = result.year {
                            Text(year)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.9 : 0.15), lineWidth: isHovering ? 2 : 1)
                )
                .shadow(color: .black.opacity(isHovering ? 0.5 : 0.3), radius: isHovering ? 15 : 8, y: isHovering ? 8 : 4)
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .aspectRatio(2.0, contentMode: .fit)
    }
}

// MARK: - Search Results (Plex Grid + TMDB Rows + Genre Rows)

struct SearchResultsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Plex Results - Adaptive grid with landscape cards
            if !viewModel.plexResults.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Results from Your Plex")
                        .font(.title2.bold())
                        .padding(.horizontal, 20)

                    // Adaptive grid of Plex results using landscape cards
                    PlexResultsGrid(items: viewModel.plexResults, onTap: onTap)
                }
                .padding(.bottom, 32)
            }

            // TMDB Movies Row
            if !viewModel.tmdbMovies.isEmpty {
                SearchHorizontalRow(
                    title: viewModel.plexResults.isEmpty ? "Top Results" : "Movies",
                    items: viewModel.tmdbMovies,
                    onTap: onTap
                )
                .padding(.bottom, 32)
            }

            // TMDB TV Shows Row
            if !viewModel.tmdbShows.isEmpty {
                SearchHorizontalRow(
                    title: "TV Shows",
                    items: viewModel.tmdbShows,
                    onTap: onTap
                )
                .padding(.bottom, 32)
            }

            // Genre Rows
            ForEach(viewModel.genreRows) { genreRow in
                SearchHorizontalRow(
                    title: genreRow.title,
                    items: genreRow.items,
                    onTap: onTap
                )
                .padding(.bottom, 32)
            }
        }
    }
}

// MARK: - Adaptive Plex Results Grid

struct PlexResultsGrid: View {
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    @State private var gridHeight: CGFloat = 200

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 40 // Account for horizontal padding
            let cardWidth: CGFloat = 360
            let spacing: CGFloat = 16
            let columns = max(1, Int((availableWidth + spacing) / (cardWidth + spacing)))

            let gridColumns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)

            LazyVGrid(columns: gridColumns, spacing: spacing) {
                ForEach(items) { result in
                    PlexLandscapeCard(result: result) {
                        onTap(result)
                    }
                }
            }
            .padding(.horizontal, 20)
            .background(
                GeometryReader { contentGeometry in
                    Color.clear.preference(
                        key: GridHeightPreferenceKey.self,
                        value: contentGeometry.size.height
                    )
                }
            )
            .onPreferenceChange(GridHeightPreferenceKey.self) { height in
                gridHeight = height
            }
        }
        .frame(height: gridHeight)
    }
}

struct GridHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 200
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


// MARK: - Plex Landscape Card (Adaptive grid item with TMDB backdrop + title)

struct PlexLandscapeCard: View {
    let result: SearchViewModel.SearchResult
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * 0.5

            Button(action: onTap) {
                ZStack(alignment: .bottomLeading) {
                    // Backdrop image (TMDB already fetched in ViewModel)
                    Group {
                        if let url = result.imageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    SkeletonView(height: height, cornerRadius: 14)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                case .failure:
                                    PlaceholderImage()
                                @unknown default:
                                    PlaceholderImage()
                                }
                            }
                        } else {
                            PlaceholderImage()
                        }
                    }
                    .frame(width: width, height: height)
                    .clipped()

                    // Gradient overlay for text readability
                    LinearGradient(
                        colors: [
                            .black.opacity(0.0),
                            .black.opacity(0.75)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Title overlay
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let year = result.year {
                            Text(year)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(isHovering ? 0.9 : 0.15), lineWidth: isHovering ? 2 : 1)
                )
                .shadow(color: .black.opacity(isHovering ? 0.5 : 0.3), radius: isHovering ? 15 : 8, y: isHovering ? 8 : 4)
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovering ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
        }
        .aspectRatio(2.0, contentMode: .fit)
    }
}

// MARK: - Horizontal Row

struct SearchHorizontalRow: View {
    let title: String
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        SearchPosterCard(item: item, width: 150) {
                            onTap(item)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

// MARK: - Search Poster Card (for horizontal rows)

struct SearchPosterCard: View {
    let item: SearchViewModel.SearchResult
    let width: CGFloat
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Poster Image
                Group {
                    if let url = item.imageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                SkeletonView(height: 225, cornerRadius: 8)
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                PlaceholderImage()
                            @unknown default:
                                PlaceholderImage()
                            }
                        }
                    } else {
                        PlaceholderImage()
                    }
                }
                .frame(width: width, height: width * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if item.available {
                        AvailableBadge()
                            .padding(6)
                    }
                }
                .shadow(color: .black.opacity(isHovering ? 0.4 : 0.2), radius: isHovering ? 12 : 6, y: isHovering ? 6 : 3)

                // Title
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Year
                if let year = item.year {
                    Text(year)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


// MARK: - Available Badge

struct AvailableBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
            Text("In Library")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.green.opacity(0.9))
        .clipShape(Capsule())
    }
}

// MARK: - Placeholder Image

struct PlaceholderImage: View {
    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Empty State View

struct EmptyStateView: View {
    let query: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No results for \"\(query)\"")
                .font(.title2.bold())

            Text("Try searching for something else")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
}

// MARK: - Search Background

struct SearchBackground: View {
    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient(
                colors: [
                    Color(hex: 0x0a0a0a),
                    Color(hex: 0x0f0f10),
                    Color(hex: 0x0b0c0d)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Subtle teal accent (top-right)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 20/255, green: 76/255, blue: 84/255, opacity: 0.28),
                    .clear
                ]),
                center: .init(x: 0.88, y: 0.10),
                startRadius: 0,
                endRadius: 600
            )

            // Subtle red accent (bottom-left)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(red: 122/255, green: 22/255, blue: 18/255, opacity: 0.30),
                    .clear
                ]),
                center: .init(x: 0.12, y: 0.88),
                startRadius: 0,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    SearchView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
        .frame(width: 1200, height: 800)
}
#endif
