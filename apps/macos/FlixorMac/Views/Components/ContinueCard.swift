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

    private var height: CGFloat {
        width * 0.5 // 2:1 aspect ratio (like web app)
    }

    private var imageURL: URL? {
        // Use TMDB backdrop if available (pre-fetched by HomeViewModel)
        if let art = item.art, let url = URL(string: art) {
            return url
        }
        // Fallback to Plex image
        return ImageService.shared.continueWatchingURL(for: item, width: Int(width * 2), height: Int(height * 2))
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
                    CachedAsyncImage(url: imageURL)
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
        }.padding(.vertical, 10)
        .buttonStyle(.plain)
        .frame(width: width)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#if DEBUG && canImport(PreviewsMacros)
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
#endif
