//
//  ContinueCard.swift
//  FlixorMac
//
//  Continue watching card with large progress bar
//

import SwiftUI

struct ContinueCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var altURL: URL? = nil

    private var height: CGFloat {
        width * 0.5 // 2:1 aspect ratio (like web app)
    }

    private var progressPercentage: Double {
        guard let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return Double(viewOffset) / Double(duration)
    }

    private var remainingTime: String {
        var parts: [String] = []

        // Add episode info for TV shows
        if item.type == "episode", let season = item.parentIndex, let episode = item.index {
            parts.append("S\(season):E\(episode)")
        }

        // Add remaining time
        if let duration = item.duration, let viewOffset = item.viewOffset {
            let remaining = duration - viewOffset
            let minutes = remaining / 60000
            if minutes > 0 {
                parts.append("\(minutes) min left")
            }
        }

        return parts.joined(separator: " • ")
    }

    var body: some View {
        Button(action: {
            onTap?()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Backdrop with play button
                ZStack {
                    CachedAsyncImage(
                        url: altURL ?? ImageService.shared.continueWatchingURL(for: item, width: Int(width * 2), height: Int(height * 2))
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.gray.opacity(0.2))

                    // Dark gradient overlay
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    // Play button
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.9 : 0.7))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.title)
                                .foregroundStyle(.black)
                                .offset(x: 3)
                        )
                        .scaleEffect(isHovered ? 1.1 : 1.0)
                        .shadow(color: .black.opacity(0.5), radius: 10)
                }
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
                )
                .shadow(color: .black.opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 15 : 8, y: isHovered ? 8 : 4)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)

                        Rectangle()
                            .fill(Color.red)
                            .frame(width: geometry.size.width * progressPercentage, height: 4)
                    }
                }
                .frame(width: width, height: 4)

                // Title and info
                VStack(alignment: .leading, spacing: 4) {
                    // For episodes, show the show name (grandparentTitle)
                    // For movies, show the movie title
                    Text(item.type == "episode" ? (item.grandparentTitle ?? item.title) : item.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(remainingTime)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: item.id) {
            await fetchTMDBBackdrop()
        }
    }

    // MARK: - TMDB Backdrop Upgrade (original size via proxy)
    private func fetchTMDBBackdrop() async {
        if let url = try? await resolveTMDBBackdropURL(for: item, width: Int(width * 2), height: Int(height * 2)) {
            await MainActor.run { self.altURL = url }
        }
    }

    private func resolveTMDBBackdropURL(for item: MediaItem, width: Int, height: Int) async throws -> URL? {
        let api = APIClient.shared
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                if let url = try await fetchTMDBBestBackdropURL(mediaType: media, id: id, width: width, height: height) {
                    return url
                }
            }
            return nil
        }
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
            struct PlexGuid: Codable { let id: String? }
            let meta: PlexMeta = try await api.get("/api/plex/metadata/\(rk)")
            let mediaType = (meta.type == "movie") ? "movie" : "tv"
            if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let tid = guid.components(separatedBy: "://").last {
                if let url = try await fetchTMDBBestBackdropURL(mediaType: mediaType, id: tid, width: width, height: height) {
                    return url
                }
            }
        }
        return nil
    }

    private func fetchTMDBBestBackdropURL(mediaType: String, id: String, width: Int, height: Int) async throws -> URL? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        let imgs: TMDBImages = try await APIClient.shared.get("/api/tmdb/\(mediaType)/\(id)/images", queryItems: [URLQueryItem(name: "language", value: "en,null")])
        let backs = imgs.backdrops ?? []
        if backs.isEmpty { return nil }
        let pick: ([TMDBImage]) -> TMDBImage? = { arr in
            return arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }
        let en = pick(backs.filter { $0.iso_639_1 == "en" })
        let nul = pick(backs.filter { $0.iso_639_1 == nil })
        let any = pick(backs)
        let sel = en ?? nul ?? any
        guard let path = sel?.file_path else { return nil }
        let full = "https://image.tmdb.org/t/p/original\(path)"
        return ImageService.shared.proxyImageURL(url: full, width: width, height: height)
    }
}

#Preview {
    HStack(spacing: 20) {
        ContinueCard(
            item: MediaItem(
                id: "1",
                title: "Breaking Bad - S1:E1 - Pilot",
                type: "episode",
                thumb: nil,
                art: "/library/metadata/1/art/123456",
                year: nil,
                rating: nil,
                duration: 2640000,
                viewOffset: 1320000,
                summary: nil,
                grandparentTitle: "Breaking Bad",
                grandparentThumb: nil,
                grandparentArt: "/library/metadata/show1/art/123",
                parentIndex: 1,
                index: 1
            ),
            width: 350
        )

        ContinueCard(
            item: MediaItem(
                id: "2",
                title: "The Matrix",
                type: "movie",
                thumb: nil,
                art: "/library/metadata/2/art/123457",
                year: 1999,
                rating: nil,
                duration: 8100000,
                viewOffset: 2025000,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil
            ),
            width: 350
        )
    }
    .padding()
    .background(Color.black)
}
