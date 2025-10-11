//
//  CarouselView.swift
//  FlixorMac
//
//  Horizontal scrolling carousel component
//

import SwiftUI

struct CarouselView<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let rowHeight: CGFloat?
    let content: (Item) -> Content

    @State private var scrollOffset: CGFloat = 0
    @State private var isHovered = false
    @State private var showLeftArrow = false
    @State private var showRightArrow = true

    init(
        items: [Item],
        itemWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        rowHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) {
        self.items = items
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.rowHeight = rowHeight
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: spacing) {
                        ForEach(items) { item in
                            content(item)
                                .frame(width: itemWidth)
                        }
                    }
                    .padding(.horizontal, 20)
                    .background(
                        GeometryReader { scrollGeometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: scrollGeometry.frame(in: .named("scroll")).origin.x
                                )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                    updateArrows(geometry: geometry)
                }

                // Navigation arrows
                if isHovered {
                    HStack {
                        if showLeftArrow {
                            navButton(direction: .left, geometry: geometry)
                        }

                        Spacer()

                        if showRightArrow {
                            navButton(direction: .right, geometry: geometry)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }

    private func navButton(direction: ScrollDirection, geometry: GeometryProxy) -> some View {
        Button(action: {
            scroll(direction: direction, geometry: geometry)
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.7))
                    .frame(width: 44, height: 44)

                Image(systemName: direction == .left ? "chevron.left" : "chevron.right")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale))
    }

    private func scroll(direction: ScrollDirection, geometry: GeometryProxy) {
        let scrollDistance = geometry.size.width * 0.7
        let newOffset = direction == .left ? scrollOffset + scrollDistance : scrollOffset - scrollDistance

        withAnimation(.easeInOut(duration: 0.3)) {
            scrollOffset = newOffset
        }
    }

    private func updateArrows(geometry: GeometryProxy) {
        let contentWidth = CGFloat(items.count) * (itemWidth + spacing)
        let visibleWidth = geometry.size.width

        showLeftArrow = scrollOffset < -20
        showRightArrow = abs(scrollOffset) + visibleWidth < contentWidth - 20
    }

    enum ScrollDirection {
        case left, right
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Carousel Row (with title)

struct CarouselRow<Item: Identifiable, Content: View>: View {
    let title: String
    let items: [Item]
    let itemWidth: CGFloat
    let spacing: CGFloat
    let showSeeAll: Bool
    let rowHeight: CGFloat?
    let content: (Item) -> Content
    var onSeeAll: (() -> Void)?

    init(
        title: String,
        items: [Item],
        itemWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        showSeeAll: Bool = true,
        rowHeight: CGFloat? = nil,
        @ViewBuilder content: @escaping (Item) -> Content,
        onSeeAll: (() -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.showSeeAll = showSeeAll
        self.rowHeight = rowHeight
        self.content = content
        self.onSeeAll = onSeeAll
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                Spacer()

                if showSeeAll {
                    Button(action: { onSeeAll?() }) {
                        HStack(spacing: 4) {
                            Text("See All")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            // Carousel
            CarouselView(
                items: items,
                itemWidth: itemWidth,
                spacing: spacing,
                rowHeight: rowHeight,
                content: content
            )
            .frame(height: rowHeight ?? (itemWidth * 1.8)) // Approximate fallback for poster cards
        }
    }
}
#if DEBUG && canImport(PreviewsMacros)
#Preview {
    let sampleItems = (1...10).map { i in
        MediaItem(
            id: "\(i)",
            title: "Movie \(i)",
            type: "movie",
            thumb: "/library/metadata/\(i)/thumb/123456",
            art: nil,
            year: 2020 + i,
            rating: 8.0,
            duration: 7200000,
            viewOffset: nil,
            summary: nil,
            grandparentTitle: nil,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
    }

    VStack(spacing: 40) {
        CarouselRow(
            title: "Popular Movies",
            items: sampleItems,
            itemWidth: 150
        ) { item in
            PosterCard(item: item, width: 150)
        }

        CarouselRow(
            title: "Continue Watching",
            items: Array(sampleItems.prefix(5)),
            itemWidth: 350,
            spacing: 16,
            rowHeight: (350 * 0.5) + 80 // approx backdrop + text
        ) { item in
            ContinueCard(item: item, width: 350)
        }
    }
    .padding(.vertical)
    .background(Color.black)
}
#endif
