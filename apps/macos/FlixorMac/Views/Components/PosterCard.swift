//
//  PosterCard.swift
//  FlixorMac
//
//  Vertical poster card for movies/shows
//

import SwiftUI

struct PosterCard: View {
    let item: MediaItem
    let width: CGFloat
    var showTitle: Bool = true
    var showProgress: Bool = false
    var onTap: (() -> Void)?

    @State private var isHovered = false

    private var height: CGFloat {
        width * 1.5 // 2:3 aspect ratio
    }

    private var progressPercentage: Double {
        guard let duration = item.duration, duration > 0,
              let viewOffset = item.viewOffset else {
            return 0
        }
        return Double(viewOffset) / Double(duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Poster Image
            Button(action: {
                onTap?()
            }) {
                ZStack(alignment: .bottom) {
                    CachedAsyncImage(
                        url: ImageService.shared.thumbURL(for: item, width: Int(width * 2), height: Int(height * 2))
                    )
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(isHovered ? 0.9 : 0.15), lineWidth: isHovered ? 2 : 1)
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.5 : 0.2), radius: isHovered ? 12 : 6, y: isHovered ? 6 : 3)

                    // Progress bar
                    if showProgress && progressPercentage > 0 {
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                Spacer()

                                ZStack(alignment: .leading) {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.3))
                                        .frame(height: 4)

                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: geometry.size.width * progressPercentage, height: 4)
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }

            // Title
            if showTitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(width: width, alignment: .leading)

                    if let year = item.year {
                        Text(String(year))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(width: width)
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    HStack(spacing: 12) {
        PosterCard(
            item: MediaItem(
                id: "1",
                title: "The Matrix",
                type: "movie",
                thumb: "/library/metadata/1/thumb/123456",
                art: nil,
                year: 1999,
                rating: 8.7,
                duration: 8100000,
                viewOffset: nil,
                summary: "A computer hacker learns about the true nature of reality.",
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil
            ),
            width: 150
        )

        PosterCard(
            item: MediaItem(
                id: "2",
                title: "Inception",
                type: "movie",
                thumb: "/library/metadata/2/thumb/123457",
                art: nil,
                year: 2010,
                rating: 8.8,
                duration: 8880000,
                viewOffset: 4440000,
                summary: nil,
                grandparentTitle: nil,
                grandparentThumb: nil,
                grandparentArt: nil,
                parentIndex: nil,
                index: nil
            ),
            width: 150,
            showProgress: true
        )
    }
    .padding()
    .background(Color.black)
}
#endif
