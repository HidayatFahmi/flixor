//
//  BillboardView.swift
//  FlixorMac
//
//  Billboard hero banner component
//

import SwiftUI

// MARK: - Billboard Image Cache
@MainActor
class BillboardImageCache {
    static let shared = BillboardImageCache()

    private var cache: [String: (backdrop: URL?, logo: URL?)] = [:]

    func get(itemId: String) -> (URL?, URL?)? {
        return cache[itemId]
    }

    func set(itemId: String, backdrop: URL?, logo: URL?) {
        cache[itemId] = (backdrop, logo)
    }

    private init() {}
}

struct BillboardView: View {
    let item: MediaItem
    var onPlay: (() -> Void)?
    var onInfo: (() -> Void)?
    var onMyList: (() -> Void)?
    var isInMyList: Bool = false

    @State private var isHovered = false
    @State private var altURL: URL? = nil
    @State private var logoURL: URL? = nil

    // Fixed height to prevent overflow
    private let billboardHeight: CGFloat = 1000

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Image (prefer TMDB-en title backdrops)
            GeometryReader { geometry in
                CachedAsyncImage(
                    url: altURL ?? ImageService.shared.artURL(
                        for: item,
                        width: Int(geometry.size.width * 2),
                        height: Int(billboardHeight * 2)
                    )
                )
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: billboardHeight)
                .clipped()
                .background(Color.black)
            }

            // Web-style gradient overlays
            // Bottom-heavy vertical gradient
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Left-to-right gradient for readability on left/center content
            LinearGradient(
                colors: [
                    Color.black.opacity(0.80),
                    Color.black.opacity(0.30),
                    Color.black.opacity(0.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Content Overlay
            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                // Title / Logo
                Group {
                    if let logoURL = logoURL {
                        CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                            .frame(maxWidth: 520)
                            .shadow(color: .black.opacity(0.6), radius: 12)
                    } else {
                        Text(item.title)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 12)
                    }
                }

                // Metadata
                HStack(spacing: 12) {
                    if let rating = item.rating {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .fontWeight(.semibold)
                        }
                    }

                    if let year = item.year {
                        Text(String(year))
                    }

                    if let duration = item.duration {
                        Text(formatDuration(duration))
                    }

                    Text(item.type.capitalized)
                }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.6), radius: 6)

                // Summary (truncated)
                if let summary = item.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(3)
                        .frame(maxWidth: 680, alignment: .leading)
                        .shadow(color: .black.opacity(0.6), radius: 6)
                }

                // Buttons
                HStack(spacing: 16) {
                    // Play Button
                    Button(action: {
                        onPlay?()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.title3)
                            Text("Play")
                                .font(.headline)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isHovered ? 1.05 : 1.0)

                    // My List Button
                    Button(action: {
                        onMyList?()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: isInMyList ? "checkmark" : "plus")
                                .font(.title3)
                            Text("My List")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.25))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Info Button
                    Button(action: {
                        onInfo?()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.title3)
                            Text("More Info")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.25))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            }
            .padding(40)
            .padding(.bottom, 20)
        }
        .frame(height: billboardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .background(Color.black.opacity(0.4))
        .shadow(color: .black.opacity(0.65), radius: 40, y: 24)
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: item.id) {
            // Check cache first
            if let cached = BillboardImageCache.shared.get(itemId: item.id) {
                self.altURL = cached.0
                self.logoURL = cached.1
            } else {
                await loadTMDBHeroImages()
            }
        }
    }

    private func formatDuration(_ milliseconds: Int) -> String {
        let minutes = milliseconds / 60000
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - TMDB Title Backdrop Resolution

extension BillboardView {
    private func loadTMDBHeroImages() async {
        do {
            if let (backdrop, logo) = try await resolveTMDBSelectedImages(for: item) {
                await MainActor.run {
                    self.altURL = backdrop
                    self.logoURL = logo
                    // Cache the result
                    BillboardImageCache.shared.set(itemId: item.id, backdrop: backdrop, logo: logo)
                }
            }
        } catch {
            // Silent fallback to Plex art - cache empty result to avoid retrying
            BillboardImageCache.shared.set(itemId: item.id, backdrop: nil, logo: nil)
        }
    }

    private func resolveTMDBSelectedImages(for item: MediaItem) async throws -> (URL?, URL?)? {
        if item.id.hasPrefix("tmdb:") {
            let parts = item.id.split(separator: ":")
            if parts.count == 3 {
                let media = (parts[1] == "movie") ? "movie" : "tv"
                let id = String(parts[2])
                return try await fetchTMDBBackdropAndLogo(mediaType: media, id: id)
            }
            return nil
        }
        if item.id.hasPrefix("plex:") {
            let rk = String(item.id.dropFirst(5))
            struct PlexMeta: Codable { let type: String?; let Guid: [PlexGuid]? }
            struct PlexGuid: Codable { let id: String? }
            let meta: PlexMeta = try await APIClient.shared.get("/api/plex/metadata/\(rk)")
            let mediaType = (meta.type == "movie") ? "movie" : "tv"
            if let guid = meta.Guid?.compactMap({ $0.id }).first(where: { $0.contains("tmdb://") || $0.contains("themoviedb://") }),
               let tid = guid.components(separatedBy: "://").last {
                return try await fetchTMDBBackdropAndLogo(mediaType: mediaType, id: tid)
            }
        }
        return nil
    }

    private func fetchTMDBBackdropAndLogo(mediaType: String, id: String) async throws -> (URL?, URL?) {
        struct TMDBImages: Codable { let backdrops: [TMDBImage]?; let logos: [TMDBImage]? }
        struct TMDBImage: Codable { let file_path: String?; let iso_639_1: String?; let vote_average: Double? }
        let imgs: TMDBImages = try await APIClient.shared.get("/api/tmdb/\(mediaType)/\(id)/images", queryItems: [URLQueryItem(name: "language", value: "en,hi,null")])
        print("✅ [IMGS] Response body: \(imgs)...")

        // Pick backdrop
        let backs = imgs.backdrops ?? []
        let pick: ([TMDBImage]) -> TMDBImage? = { arr in
            return arr.sorted { ($0.vote_average ?? 0) > ($1.vote_average ?? 0) }.first
        }
        let enB = pick(backs.filter { $0.iso_639_1 == "en" })
        let nulB = pick(backs.filter { $0.iso_639_1 == nil })
        let anyB = pick(backs)
        let selB = anyB
        let backdropURL: URL? = {
            guard let path = selB?.file_path else { return nil }
            let full = "https://image.tmdb.org/t/p/original\(path)"
            return ImageService.shared.proxyImageURL(url: full)
        }()

        // Pick logo (prefer English), use w500 for logos
        let logos = imgs.logos ?? []
        let enL = logos.first { $0.iso_639_1 == "en" }
        let anyL = logos.first
        let selL = enL ?? anyL
        let logoURL: URL? = {
            guard let path = selL?.file_path else { return nil }
            let full = "https://image.tmdb.org/t/p/w500\(path)"
            return ImageService.shared.proxyImageURL(url: full)
        }()

        return (backdropURL, logoURL)
    }
}

#Preview {
    BillboardView(
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
            summary: "A computer hacker learns from mysterious rebels about the true nature of his reality and his role in the war against its controllers.",
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        ),
        onPlay: { print("Play") },
        onInfo: { print("Info") },
        onMyList: { print("My List") }
    )
    .background(Color.black)
}
