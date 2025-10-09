//
//  CollectionsView.swift
//  FlixorMac
//
//  Grid view for Plex collections.
//

import SwiftUI

struct CollectionsView: View {
    let collections: [LibraryViewModel.CollectionEntry]
    let isLoading: Bool
    var onSelect: (LibraryViewModel.CollectionEntry) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 20)]

    var body: some View {
        if isLoading {
            loadingState
        } else if collections.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(collections) { collection in
                        Button {
                            onSelect(collection)
                        } label: {
                            collectionCard(for: collection)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 32)
            }
        }
    }

    private var loadingState: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonView(height: 240, cornerRadius: 18)
                        .frame(height: 240)
                }
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.person.crop")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No collections available")
                .font(.title2.weight(.semibold))
            Text("Create collections in Plex to see them here.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private func collectionCard(for collection: LibraryViewModel.CollectionEntry) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: collection.artwork)
                .aspectRatio(16/9, contentMode: .fill)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0.75), Color.black.opacity(0)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(collection.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(collection.count) \(collection.count == 1 ? "item" : "items")")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18), in: Capsule())
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
    }
}

#Preview {
    CollectionsView(
        collections: [
            .init(id: "1", title: "Christopher Nolan Collection", artwork: URL(string: "https://image.tmdb.org/t/p/w500/qmDpIHrmpJINaRKAfWQfftjCdyi.jpg"), count: 14),
            .init(id: "2", title: "Animated Favourites", artwork: URL(string: "https://image.tmdb.org/t/p/w500/2uNW4WbgBXL25BAbXGLnLqX71Sw.jpg"), count: 32)
        ],
        isLoading: false,
        onSelect: { _ in }
    )
    .background(Color.black)
}
