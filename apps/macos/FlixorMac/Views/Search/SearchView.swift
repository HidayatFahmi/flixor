//
//  SearchView.swift
//  FlixorMac
//
//  Search screen with Popular/Trending and live search results
//

import SwiftUI

struct SearchView: View {
    @StateObject private var viewModel = SearchViewModel()
    @State private var selectedDetails: MediaItem? = nil
    @State private var goDetails: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            SearchBackground()

            ScrollView {
                VStack(spacing: 0) {
                    // Hidden link for navigation to Details
                    NavigationLink(destination: OptionalSearchDetailsDestination(item: selectedDetails), isActive: $goDetails) {
                        EmptyView()
                    }
                    .frame(width: 0, height: 0)
                    .hidden()

                    // Spacer for top nav bar
                    Color.clear.frame(height: 72)

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
                            if viewModel.searchResults.isEmpty {
                                EmptyStateView(query: viewModel.query)
                            } else {
                                SearchResultsView(viewModel: viewModel, onTap: { item in
                                    navigateToDetails(item: item)
                                })
                            }
                        }
                    }
                    .padding(.top, 24)
                }
            }

            // Top Navigation Bar
            TopNavBar(scrollOffset: .constant(0))
                .environmentObject(SessionManager.shared)
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
        selectedDetails = MediaItem(
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
        goDetails = true
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

// MARK: - Idle State (Popular + Trending)

struct IdleStateView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    var body: some View {
        VStack(spacing: 40) {
            // Popular
            if !viewModel.popularItems.isEmpty {
                SearchSectionView(
                    title: "Popular on Plex",
                    items: viewModel.popularItems,
                    onTap: onTap
                )
            }

            // Trending
            if !viewModel.trendingItems.isEmpty {
                SearchSectionView(
                    title: "Trending Now",
                    items: viewModel.trendingItems,
                    onTap: onTap
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Search Results Grid

struct SearchResultsView: View {
    @ObservedObject var viewModel: SearchViewModel
    let onTap: (SearchViewModel.SearchResult) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Results")
                .font(.title2.bold())
                .padding(.horizontal, 20)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.searchResults) { result in
                    SearchResultCard(result: result) {
                        onTap(result)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Search Section (for Popular/Trending)

struct SearchSectionView: View {
    let title: String
    let items: [SearchViewModel.SearchResult]
    let onTap: (SearchViewModel.SearchResult) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(items.prefix(12)) { result in
                    SearchResultCard(result: result) {
                        onTap(result)
                    }
                }
            }
        }
    }
}

// MARK: - Search Result Card

struct SearchResultCard: View {
    let result: SearchViewModel.SearchResult
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Poster Image
                Group {
                    if let url = result.imageURL {
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
                .frame(width: 150, height: 225)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if result.available {
                        AvailableBadge()
                            .padding(6)
                    }
                }
                .shadow(color: .black.opacity(isHovering ? 0.4 : 0.2), radius: isHovering ? 12 : 6, y: isHovering ? 6 : 3)

                // Title
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                // Year
                if let year = result.year {
                    Text(year)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 150)
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

// MARK: - Optional Details Destination

private struct OptionalSearchDetailsDestination: View {
    let item: MediaItem?

    var body: some View {
        Group {
            if let item = item {
                DetailsView(item: item)
            } else {
                EmptyView()
            }
        }
    }
}

#Preview {
    SearchView()
        .environmentObject(SessionManager.shared)
        .environmentObject(APIClient.shared)
        .frame(width: 1200, height: 800)
}
