//
//  NewPopularHero.swift
//  FlixorMac
//
//  Hero banner for New & Popular screen
//

import SwiftUI

struct NewPopularHero: View {
    let data: HeroData
    var onPlay: (() -> Void)?
    var onMoreInfo: (() -> Void)?
    var onMyList: (() -> Void)?
    var isInMyList: Bool = false

    @State private var isHovered = false

    private let heroHeight: CGFloat = 700

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Backdrop Image
            GeometryReader { geometry in
                if let backdropURL = data.backdropURL {
                    CachedAsyncImage(url: backdropURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: heroHeight)
                        .clipped()
                } else {
                    Color.gray.opacity(0.3)
                        .frame(width: geometry.size.width, height: heroHeight)
                }
            }

            // Gradient overlays for readability
            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

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

                // Title or Logo
                Group {
                    if let logoURL = data.logoURL {
                        CachedAsyncImage(url: logoURL, aspectRatio: nil, contentMode: .fit)
                            .frame(maxWidth: 480, maxHeight: 140)
                            .shadow(color: .black.opacity(0.6), radius: 12)
                    } else {
                        Text(data.title)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 12)
                    }
                }

                // Metadata row
                HStack(spacing: 12) {
                    if let rating = data.rating {
                        Text(rating)
                            .fontWeight(.semibold)
                    }

                    if let year = data.year {
                        Text(year)
                    }

                    if let runtime = data.runtime {
                        Text(formatRuntime(runtime))
                    }

                    if !data.genres.isEmpty {
                        Text(data.genres.prefix(3).joined(separator: ", "))
                            .lineLimit(1)
                    }
                }
                .font(.headline)
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.6), radius: 6)

                // Overview (truncated to 3 lines)
                if !data.overview.isEmpty {
                    Text(data.overview)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(3)
                        .frame(maxWidth: 680, alignment: .leading)
                        .shadow(color: .black.opacity(0.6), radius: 6)
                }

                // Action Buttons
                HStack(spacing: 16) {
                    // Play Button (only if available on Plex)
                    if data.canPlay {
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
                    }

                    // More Info Button
                    Button(action: {
                        onMoreInfo?()
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

                    // Trailer Button (if available)
                    if let ytKey = data.ytKey {
                        Button(action: {
                            openYouTubeTrailer(ytKey)
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.rectangle")
                                    .font(.title3)
                                Text("Trailer")
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
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 40)
        }
        .frame(height: heroHeight)
        .background(Color.black)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatRuntime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func openYouTubeTrailer(_ ytKey: String) {
        let urlString = "https://www.youtube.com/watch?v=\(ytKey)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    NewPopularHero(
        data: HeroData(
            id: "tmdb:movie:603",
            title: "The Matrix",
            overview: "Set in the 22nd century, The Matrix tells the story of a computer hacker who joins a group of underground insurgents fighting the vast and powerful computers who now rule the earth.",
            backdropURL: nil,
            posterURL: nil,
            rating: "⭐ 8.2",
            year: "1999",
            runtime: 136,
            genres: ["Action", "Science Fiction"],
            ytKey: "vKQi3bBA1y8",
            logoURL: nil,
            canPlay: false,
            mediaType: "movie"
        ),
        onPlay: { print("Play") },
        onMoreInfo: { print("More Info") },
        onMyList: { print("My List") }
    )
    .frame(height: 700)
    .background(Color.black)
}
#endif
