//
//  LandscapeCard.swift
//  FlixorMac
//
//  Generic landscape (backdrop) card used for rows like On Deck and Recently Added
//

import SwiftUI

struct LandscapeCard: View {
    let item: MediaItem
    let width: CGFloat
    var onTap: (() -> Void)?

    @State private var isHovered = false
    @State private var altURL: URL? = nil

    private var height: CGFloat {
        width * 0.5 // 2:1 aspect to match web rows
    }

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    // Backdrop image — use same pipeline as ContinueCard
                    CachedAsyncImage(url: altURL ?? ImageService.shared.continueWatchingURL(for: item, width: Int(width * 2), height: Int(height * 2)))
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.gray.opacity(0.2))

                    // Subtle hover zoom
                    Color.clear
                        .frame(width: width, height: height)
                        .overlay(
                            LinearGradient(
                                colors: [
                                    .black.opacity(0.0),
                                    .black.opacity(0.75)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Title overlay
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if let label = item.episodeLabel {
                            Text(label)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                }
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
                )
                .shadow(color: .black.opacity(isHovered ? 0.5 : 0.3), radius: isHovered ? 15 : 8, y: isHovered ? 8 : 4)
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
        print("🎬 [LandscapeCard] Fetching TMDB backdrop for: \(item.title) (id: \(item.id))")
        // Only attempt upgrade when underlying image is Plex-based or missing
        // Try to resolve TMDB backdrop via metadata mapping
        if let url = try? await resolveTMDBBackdropURL(for: item, width: Int(width * 2), height: Int(height * 2)) {
            print("✅ [LandscapeCard] Got TMDB backdrop for: \(item.title)")
            await MainActor.run { self.altURL = url }
        } else {
            print("❌ [LandscapeCard] No TMDB backdrop for: \(item.title), using Plex image")
        }
    }

    private func resolveTMDBBackdropURL(for item: MediaItem, width: Int, height: Int) async throws -> URL? {
        // Case 1: TMDB id already encoded in item.id (tmdb:movie:123 or tmdb:tv:123)
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

        // Case 2: Plex item with plex: prefix – resolve TMDB guid from metadata
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            return try await fetchTMDBBackdropForPlexItem(ratingKey: rk, width: width, height: height)
        }

        // Case 3: Raw numeric ID (Plex rating key without prefix)
        // This happens for library items loaded from /api/plex/library/{key}/all
        if item.id.allSatisfy({ $0.isNumber }) {
            print("🔍 [LandscapeCard] Detected numeric ID, treating as Plex rating key: \(item.id)")
            return try await fetchTMDBBackdropForPlexItem(ratingKey: item.id, width: width, height: height)
        }

        return nil
    }

    private func fetchTMDBBackdropForPlexItem(ratingKey: String, width: Int, height: Int) async throws -> URL? {
        let api = APIClient.shared
        struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
        struct PlexGuid: Codable { let id: String? }

        let meta: PlexMeta = try await api.get("/api/plex/metadata/\(ratingKey)")
        let mediaType = (meta.type == "movie") ? "movie" : "tv"

        if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
           let tid = guid.components(separatedBy: "://").last {
            return try await fetchTMDBBestBackdropURL(mediaType: mediaType, id: tid, width: width, height: height)
        }
        return nil
    }

    private func fetchTMDBBestBackdropURL(mediaType: String, id: String, width: Int, height: Int) async throws -> URL? {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        let api = APIClient.shared
        let imgs: TMDBImages = try await api.get("/api/tmdb/\(mediaType)/\(id)/images", queryItems: [URLQueryItem(name: "language", value: "en,hi,null")])
        let backs = imgs.backdrops ?? []
        if backs.isEmpty { return nil }
        let pick: ([TMDBImage]) -> TMDBImage? = { arr in
            return arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }
        // Priority: en/hi with titles > null (no text) > any other language
        let en = pick(backs.filter { $0.iso_639_1 == "en" })
        let hi = pick(backs.filter { $0.iso_639_1 == "hi" })
        let nul = pick(backs.filter { $0.iso_639_1 == nil })
        let any = pick(backs)
        let sel = en ?? hi ?? nul ?? any
        guard let path = sel?.file_path else { return nil }
        let full = "https://image.tmdb.org/t/p/original\(path)"
        return ImageService.shared.proxyImageURL(url: full, width: width, height: height)
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HStack(spacing: 20) {
        LandscapeCard(
            item: MediaItem(
                id: "1",
                title: "The Matrix",
                type: "movie",
                thumb: nil,
                art: "/library/metadata/1/art/123456",
                year: 1999,
                rating: 8.7,
                duration: 8100000,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil
            ),
            width: 420
        )

        LandscapeCard(
            item: MediaItem(
                id: "2",
                title: "Breaking Bad - S1:E2",
                type: "episode",
                thumb: nil,
                art: "/library/metadata/2/art/123457",
                year: nil,
                rating: nil,
                duration: nil,
                viewOffset: nil,
                summary: nil,
                grandparentTitle: "Breaking Bad",
                grandparentThumb: nil,
                grandparentArt: "/library/metadata/show1/art/123",
                parentIndex: 1,
                index: 2
            ),
            width: 420
        )
    }
    .padding()
    .background(Color.black)
}
#endif
