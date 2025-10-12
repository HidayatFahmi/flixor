//
//  DetailsView.swift
//  FlixorMac
//
//  Minimal details page to enable navigation from Home
//

import SwiftUI

private struct DetailsLayoutMetrics {
    let width: CGFloat

    var heroHeight: CGFloat {
        switch width {
        case ..<900: return 600
        case ..<1200: return 660
        case ..<1500: return 720
        default: return 1200
        }
    }

    var heroHorizontalPadding: CGFloat {
        switch width {
        case ..<900: return 32
        case ..<1200: return 44
        case ..<1600: return 60
        default: return 72
        }
    }

    var heroTopPadding: CGFloat {
        switch width {
        case ..<900: return 68
        case ..<1200: return 88
        default: return 216
        }
    }

    var heroBottomPadding: CGFloat {
        switch width {
        case ..<900: return 56
        case ..<1400: return 72
        default: return 88
        }
    }

    var heroTextMaxWidth: CGFloat {
        min(width * 0.52, 640)
    }

    var contentPadding: CGFloat {
        switch width {
        case ..<900: return 20
        case ..<1200: return 20
        default: return 20
        }
    }

    var tabsPadding: CGFloat {
        switch width {
        case ..<900: return 20
        case ..<1200: return 20
        default: return 20
        }
    }

    var contentMaxWidth: CGFloat {
        min(width - contentPadding * 2, 1320)
    }

    var infoGridColumns: Int {
        if width >= 1320 { return 3 }
        if width >= 960 { return 2 }
        return 1
    }

    var technicalGridMinimum: CGFloat {
        if width >= 1500 { return 240 }
        if width >= 1200 { return 220 }
        if width >= 960 { return 200 }
        return 180
    }

    var castGridMinimum: CGFloat {
        if width >= 1500 { return 180 }
        if width >= 1200 { return 170 }
        if width >= 960 { return 160 }
        return 150
    }

    var extraCardMinimum: CGFloat {
        if width >= 1400 { return 300 }
        if width >= 1100 { return 260 }
        if width >= 900 { return 220 }
        return 200
    }

    var episodeThumbnailWidth: CGFloat {
        if width >= 1500 { return 260 }
        if width >= 1250 { return 240 }
        if width >= 1000 { return 220 }
        if width >= 820 { return 200 }
        return 180
    }
}

struct DetailsView: View {
    let item: MediaItem
    @StateObject private var vm = DetailsViewModel()
    @State private var activeTab: String = "SUGGESTED"
    @StateObject private var browseViewModel = BrowseModalViewModel()
    @State private var showBrowseModal = false
    @State private var activeBrowseContext: BrowseContext?
    @EnvironmentObject private var router: NavigationRouter
    @EnvironmentObject private var mainView: MainViewState

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 640)
                let layout = DetailsLayoutMetrics(width: width)

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 0) {
                            DetailsHeroSection(
                                vm: vm,
                                onPlay: playContent,
                                layout: layout
                            )

                            DetailsTabsBar(tabs: tabsData, activeTab: $activeTab)
                        }

                        VStack(spacing: 32) {
                            switch activeTab {
                            case "SUGGESTED":
                                SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                                    presentBrowse(context)
                                })
                            case "DETAILS":
                                DetailsTabContent(vm: vm, layout: layout)
                            case "EPISODES":
                                EpisodesTabContent(vm: vm, layout: layout, onPlayEpisode: playEpisode)
                            case "EXTRAS":
                                ExtrasTabContent(vm: vm, layout: layout)
                            default:
                                SuggestedSections(vm: vm, layout: layout, onBrowse: { context in
                                    presentBrowse(context)
                                })
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, layout.contentPadding)
                        .padding(.bottom, 32)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)

            if showBrowseModal {
                BrowseModalView(
                    isPresented: $showBrowseModal,
                    viewModel: browseViewModel,
                    onSelect: { media in
                        showBrowseModal = false
                        Task {
                            await vm.load(for: media)
                            await MainActor.run {
                                activeTab = (vm.mediaKind == "tv") ? "EPISODES" : "SUGGESTED"
                            }
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(HomeBackground())
        .navigationTitle("")
        .task {
            await vm.load(for: item)
            if vm.mediaKind == "tv" { activeTab = "EPISODES" }
        }
        .onChange(of: showBrowseModal) { value in
            if !value {
                activeBrowseContext = nil
                browseViewModel.reset()
            }
        }
        // Destination for PlayerView is handled at root via NavigationStack(path:)
    }

    private func playContent() {
        // If we have a playableId from the ViewModel, use it
        if let playableId = vm.playableId {
            // CRITICAL: Preserve episode type from original item
            // vm.mediaKind only stores "movie" or "tv", but episodes need type="episode"
            let mediaType: String = {
                if item.type == "episode" {
                    return "episode"
                }
                return vm.mediaKind ?? item.type
            }()

            let playerItem = MediaItem(
                id: playableId,
                title: vm.title.isEmpty ? item.title : vm.title,
                type: mediaType,
                thumb: item.thumb,
                art: item.art,
                year: vm.year.flatMap { Int($0) },
                rating: nil,
                duration: vm.runtime.map { $0 * 60000 },
                viewOffset: nil,
                summary: vm.overview.isEmpty ? nil : vm.overview,
                grandparentTitle: item.grandparentTitle,
                grandparentThumb: item.grandparentThumb,
                grandparentArt: item.grandparentArt,
                parentIndex: item.parentIndex,
                index: item.index
            )
            appendToCurrentTabPath(playerItem)
        } else {
            appendToCurrentTabPath(item)
        }
    }

    private func appendToCurrentTabPath(_ item: MediaItem) {
        switch mainView.selectedTab {
        case .home: router.homePath.append(item)
        case .search: router.searchPath.append(item)
        case .library: router.libraryPath.append(item)
        case .myList: router.myListPath.append(item)
        case .newPopular: router.newPopularPath.append(item)
        }
    }

    private func presentBrowse(_ context: BrowseContext) {
        activeBrowseContext = context
        showBrowseModal = true
        Task {
            await browseViewModel.load(context: context)
        }
    }

    private func playEpisode(_ episode: DetailsViewModel.Episode) {
        let playerItem = MediaItem(
            id: episode.id,
            title: episode.title,
            type: "episode",
            thumb: episode.image?.absoluteString,
            art: nil,
            year: nil,
            rating: nil,
            duration: episode.durationMin.map { $0 * 60000 },
            viewOffset: episode.viewOffset,
            summary: episode.overview,
            grandparentTitle: vm.title.isEmpty ? nil : vm.title,
            grandparentThumb: nil,
            grandparentArt: nil,
            parentIndex: nil,
            index: nil
        )
        appendToCurrentTabPath(playerItem)
    }
}

// MARK: - Hero Section

private struct DetailsHeroSection: View {
    @ObservedObject var vm: DetailsViewModel
    let onPlay: () -> Void
    let layout: DetailsLayoutMetrics

    @State private var isOverviewExpanded = false

    private var metaItems: [String] {
        var parts: [String] = []
        if let y = vm.year, !y.isEmpty { parts.append(y) }
        if let runtime = formattedRuntime(vm.runtime) { parts.append(runtime) }
        if let rating = vm.rating, !rating.isEmpty { parts.append(rating) }
        return parts
    }

    private func formattedRuntime(_ minutes: Int?) -> String? {
        guard let minutes = minutes, minutes > 0 else { return nil }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }

    private func hasRatings(_ ratings: DetailsViewModel.ExternalRatings) -> Bool {
        if let score = ratings.imdb?.score, score > 0 { return true }
        if let critic = ratings.rottenTomatoes?.critic, critic > 0 { return true }
        if let audience = ratings.rottenTomatoes?.audience, audience > 0 { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                CachedAsyncImage(url: vm.backdropURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, minHeight: layout.heroHeight, alignment: .center)
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [Color.black.opacity(0.78), Color.black.opacity(0.35), Color.black.opacity(0.08)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                RadialGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.6), .clear]),
                    center: .init(x: -0.1, y: 0.4),
                    startRadius: 10,
                    endRadius: 900
                )
            }
            .frame(height: layout.heroHeight)
            .clipped()

            VStack(alignment: .leading, spacing: heroSpacing) {
                if let logo = vm.logoURL {
                    CachedAsyncImage(url: logo, contentMode: .fit)
                        .frame(maxWidth: logoWidth)
                        .shadow(color: .black.opacity(0.7), radius: 16, y: 6)
                } else {
                    Text(vm.title)
                        .font(.system(size: titleFontSize, weight: .heavy))
                        .kerning(0.4)
                        .shadow(color: .black.opacity(0.6), radius: 12)
                }

                if !(metaItems.isEmpty && vm.badges.isEmpty && !(vm.externalRatings.map(hasRatings) ?? false)) {
                    ViewThatFits {
                        HStack(spacing: 12) { metaRow }
                        VStack(alignment: .leading, spacing: 10) { metaRow }
                    }
                }

                if !vm.overview.isEmpty {
                    CollapsibleOverview(
                        text: vm.overview,
                        maxWidth: layout.heroTextMaxWidth,
                        isExpanded: $isOverviewExpanded
                    )
                }

                ViewThatFits {
                    HStack(alignment: .top, spacing: heroFactSpacing) { heroFacts }
                    VStack(alignment: .leading, spacing: 16) { heroFacts }
                }

                ViewThatFits {
                    HStack(spacing: actionSpacing) { actionButtons }
                    VStack(alignment: .leading, spacing: 12) { actionButtons }
                }
            }
            .padding(.leading, layout.heroHorizontalPadding)
            .padding(.trailing, heroTrailingPadding)
            .padding(.top, layout.heroTopPadding)
            .padding(.bottom, layout.heroBottomPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: layout.heroHeight)
    }

    private var canonicalWatchlistId: String? {
        if let playable = vm.playableId { return playable }
        if let tmdb = vm.tmdbId {
            let prefix = (vm.mediaKind == "tv") ? "tmdb:tv:" : "tmdb:movie:"
            return prefix + tmdb
        }
        return nil
    }

    private var watchlistMediaType: MyListViewModel.MediaType? {
        if vm.mediaKind == "tv" { return .show }
        if vm.mediaKind == "movie" { return .movie }
        return .movie
    }

    private var castSummary: String {
        if vm.cast.isEmpty { return "—" }
        let names = vm.castShort.map { $0.name }
        let summary = names.joined(separator: ", ")
        if vm.castMoreCount > 0 {
            return summary + " +\(vm.castMoreCount) more"
        }
        return summary
    }

    @ViewBuilder
    private func heroFactBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
        }
    }

    private var width: CGFloat { layout.width }

    private var heroSpacing: CGFloat {
        width < 1100 ? 20 : 26
    }

    private var heroFactSpacing: CGFloat {
        width < 1100 ? 20 : 26
    }

    private var actionSpacing: CGFloat {
        width < 820 ? 12 : 16
    }

    private var titleFontSize: CGFloat {
        if width < 820 { return 36 }
        if width < 1100 { return 42 }
        return 48
    }

    private var logoWidth: CGFloat {
        if width < 900 { return 340 }
        if width < 1300 { return 420 }
        return 480
    }

    private var heroTrailingPadding: CGFloat {
        width < 1100 ? layout.heroHorizontalPadding : 48
    }

    @ViewBuilder private var metaRow: some View {
        if !metaItems.isEmpty {
            Text(metaItems.joined(separator: " • "))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        ForEach(vm.badges, id: \.self) { badge in
            HeroMetaPill(text: badge)
        }
        if let ratings = vm.externalRatings, hasRatings(ratings) {
            RatingsStrip(ratings: ratings)
        }
    }

    @ViewBuilder private var heroFacts: some View {
        heroFactBlock(title: "Cast", value: castSummary)
        heroFactBlock(title: "Genres", value: vm.genres.isEmpty ? "—" : vm.genres.joined(separator: ", "))
        heroFactBlock(title: vm.mediaKind == "tv" ? "This Show Is" : "This Movie Is", value: vm.moodTags.isEmpty ? "—" : vm.moodTags.joined(separator: ", "))
    }

    @ViewBuilder private var actionButtons: some View {
        Button(action: onPlay) {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Play").fontWeight(.semibold)
            }
            .font(.system(size: 16))
            .foregroundStyle(.black)
            .padding(.horizontal, 26)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)

        if let watchlistId = canonicalWatchlistId,
           let mediaType = watchlistMediaType {
            WatchlistButton(
                canonicalId: watchlistId,
                mediaType: mediaType,
                plexRatingKey: vm.plexRatingKey,
                plexGuid: vm.plexGuid,
                tmdbId: vm.tmdbId,
                imdbId: nil,
                title: vm.title,
                year: vm.year.flatMap { Int($0) },
                style: .pill
            )
        }
    }
}

// MARK: - Tab Content Helpers

private struct SuggestedSections: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    var onBrowse: ((BrowseContext) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: layout.width < 1100 ? 24 : 28) {
            if !vm.related.isEmpty {
                LandscapeSectionView(
                    section: LibrarySection(
                        id: "rel",
                        title: "Related",
                        items: vm.related,
                        totalCount: vm.related.count,
                        libraryKey: nil,
                        browseContext: vm.relatedBrowseContext
                    ),
                    onTap: { media in
                    Task { await vm.load(for: media) }
                },
                    onBrowse: { context in
                        onBrowse?(context)
                    }
                )
                .padding(.trailing, 60)
            }
            if !vm.similar.isEmpty {
                LandscapeSectionView(
                    section: LibrarySection(
                        id: "sim",
                        title: "Similar",
                        items: vm.similar,
                        totalCount: vm.similar.count,
                        libraryKey: nil,
                        browseContext: vm.similarBrowseContext
                    ),
                    onTap: { media in
                    Task { await vm.load(for: media) }
                },
                    onBrowse: { context in
                        onBrowse?(context)
                    }
                )
                .padding(.trailing, 60)
            }
        }
    }
}

private struct DetailsTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            // About Section
            VStack(alignment: .leading, spacing: 20) {
                DetailsSectionHeader(title: "About")

                VStack(alignment: .leading, spacing: 16) {
                    // Overview
                    if !vm.overview.isEmpty {
                        Text(vm.overview)
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    // Metadata badges
                    if vm.year != nil || vm.runtime != nil || vm.rating != nil {
                        HStack(spacing: 10) {
                            if let y = vm.year {
                                MetadataBadge(icon: "calendar", text: y)
                            }
                            if let rt = vm.runtime {
                                MetadataBadge(icon: "clock", text: formattedRuntime(rt))
                            }
                            if let cr = vm.rating {
                                MetadataBadge(icon: "star.fill", text: cr)
                            }
                        }
                    }
                }
            }

            // Info Grid
            VStack(alignment: .leading, spacing: 20) {
                DetailsSectionHeader(title: "Info")

                HStack(alignment: .bottom, spacing: 24) {
                    // Cast
                    InfoColumn(
                        title: "Cast",
                        content: castContent()
                    )

                    // Genres
                    InfoColumn(
                        title: "Genres",
                        content: vm.genres.isEmpty ? "—" : vm.genres.joined(separator: ", ")
                    )

                    // Mood Tags
                    InfoColumn(
                        title: vm.mediaKind == "tv" ? "This Show Is" : "This Movie Is",
                        content: vm.moodTags.isEmpty ? "—" : vm.moodTags.joined(separator: ", ")
                    )
                }
            }

            // Technical Details
            if let version = vm.activeVersionDetail {
                TechnicalDetailsSection(version: version, layout: layout)
            }

            // Cast & Crew
            if !vm.cast.isEmpty || !vm.crew.isEmpty {
                CastCrewSection(cast: vm.cast, crew: vm.crew, layout: layout)
            }
        }
    }

    private var infoGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: layout.infoGridColumns)
    }

    private func castContent() -> String {
        if vm.cast.isEmpty { return "—" }
        let names = vm.showAllCast ? vm.cast.map { $0.name } : vm.castShort.map { $0.name }
        let joined = names.joined(separator: ", ")
        if vm.castMoreCount > 0 && !vm.showAllCast {
            return joined + " and \(vm.castMoreCount) more"
        }
        return joined
    }

    private func formattedRuntime(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Info Column Component
private struct InfoColumn: View {
    let title: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .textCase(.uppercase)

            Text(content)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Metadata Badge Component
private struct MetadataBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct EpisodesTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics
    let onPlayEpisode: (DetailsViewModel.Episode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if vm.seasons.count > 1 {
                HStack {
                    Picker("Season", selection: Binding<String>(
                        get: { vm.selectedSeasonKey ?? "" },
                        set: { newVal in Task { await vm.selectSeason(newVal) } }
                    )) {
                        ForEach(vm.seasons) { s in
                            Text(s.title).tag(s.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: seasonPickerWidth, alignment: .leading)
                    Spacer()
                }
            }

            if vm.episodesLoading {
                ProgressView().progressViewStyle(.circular)
            }

            if vm.episodes.isEmpty && !vm.episodesLoading {
                Text("No episodes found").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.episodes) { e in
                        EpisodeRow(
                            episode: e,
                            thumbnailWidth: layout.episodeThumbnailWidth,
                            onPlay: { onPlayEpisode(e) }
                        )
                    }
                }
            }
        }
    }

    private var seasonPickerWidth: CGFloat {
        let base = layout.episodeThumbnailWidth
        return min(260, max(160, base * 0.85))
    }
}

// MARK: - Episode Row Component
private struct EpisodeRow: View {
    let episode: DetailsViewModel.Episode
    let thumbnailWidth: CGFloat
    let onPlay: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onPlay) {
            HStack(alignment: .top, spacing: 12) {
                // Episode thumbnail with progress bar and hover overlay
                if let u = episode.image {
                    ZStack {
                        // Thumbnail
                        CachedAsyncImage(url: u)
                            .frame(width: thumbnailWidth, height: thumbnailHeight)

                        // Hover overlay
                        if isHovered {
                            Rectangle()
                                .fill(Color.black.opacity(0.25))
                                .frame(width: thumbnailWidth, height: thumbnailHeight)

                            // Play button
                            Text("Play")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .clipShape(Capsule())
                        }

                        // Progress bar (matching web implementation)
                        if let progress = episode.progressPct, progress > 0 {
                            VStack {
                                Spacer()
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(height: 6)

                                        Rectangle()
                                            .fill(Color(red: 229/255, green: 9/255, blue: 20/255))
                                            .frame(width: geometry.size.width * CGFloat(min(100, max(0, progress))) / 100.0, height: 6)
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                    .frame(width: thumbnailWidth, height: thumbnailHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.15), lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(episode.title).font(.headline)
                    if let o = episode.overview { Text(o).foregroundStyle(.secondary).lineLimit(2) }
                    HStack(spacing: 10) {
                        if let d = episode.durationMin { Text("\(d)m").foregroundStyle(.secondary) }
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var thumbnailHeight: CGFloat {
        thumbnailWidth * (9.0 / 16.0)
    }
}

private struct ExtrasTabContent: View {
    @ObservedObject var vm: DetailsViewModel
    let layout: DetailsLayoutMetrics

    var body: some View {
        if vm.extras.isEmpty {
            Text("No extras available").foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.extraCardMinimum), spacing: 16)], spacing: 16) {
                ForEach(vm.extras) { ex in
                    VStack(alignment: .leading, spacing: 8) {
                        if let u = ex.image {
                            CachedAsyncImage(url: u)
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        Text(ex.title).font(.headline)
                        if let d = ex.durationMin { Text("\(d)m").foregroundStyle(.secondary) }
                    }
                    .padding(4)
                }
            }
        }
    }
}

// MARK: - Tabs data

private extension DetailsView {
    var tabsData: [DetailsTab] {
        var t: [DetailsTab] = []
        if vm.mediaKind == "tv" { t.append(DetailsTab(id: "EPISODES", label: "Episodes", count: nil)) }
        t.append(DetailsTab(id: "SUGGESTED", label: "Suggested", count: nil))
        t.append(DetailsTab(id: "EXTRAS", label: "Extras", count: nil))
        t.append(DetailsTab(id: "DETAILS", label: "Details", count: nil))
        return t
    }
}

// MARK: - Badge helper

private struct HeroMetaPill: View {
    let text: String

    private var palette: (background: Color, foreground: Color, border: Color?) {
        switch text.lowercased() {
        case "plex":
            return (Color.white.opacity(0.18), Color.white, nil)
        case "no local source":
            return (Color.red.opacity(0.7), Color.white, nil)
        default:
            return (Color.white.opacity(0.18), Color.white, Color.white.opacity(0.2))
        }
    }

    var body: some View {
        let colors = palette
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(colors.background)
            )
            .overlay(
                Group {
                    if let border = colors.border {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(border, lineWidth: 1)
                    }
                }
            )
            .foregroundStyle(colors.foreground)
    }
}

private struct RatingsStrip: View {
    let ratings: DetailsViewModel.ExternalRatings

    var body: some View {
        HStack(spacing: 10) {
            if let imdbScore = ratings.imdb?.score {
                RatingsPill {
                    HStack(spacing: 8) {
                        IMDbMark()
                        Text(String(format: "%.1f", imdbScore))
                            .font(.system(size: 12, weight: .semibold))
                        if let votes = ratings.imdb?.votes, let display = formattedVotes(votes) {
                            Text(display)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            if let critic = ratings.rottenTomatoes?.critic {
                RatingsPill {
                    HStack(spacing: 8) {
                        TomatoIcon(score: critic)
                        Text("\(critic)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(scoreColor(critic))
                        Text("Critics")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            if let audience = ratings.rottenTomatoes?.audience {
                RatingsPill {
                    HStack(spacing: 8) {
                        PopcornIcon(score: audience)
                        Text("\(audience)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(scoreColor(audience))
                        Text("Audience")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
    }

    private func formattedVotes(_ votes: Int) -> String? {
        guard votes > 0 else { return nil }
        switch votes {
        case 1_000_000...:
            return String(format: "%.1fM", Double(votes) / 1_000_000)
        case 10_000...:
            return String(format: "%.1fk", Double(votes) / 1_000)
        case 1_000...:
            return String(format: "%.1fk", Double(votes) / 1_000)
        default:
            return NumberFormatter.localizedString(from: NSNumber(value: votes), number: .decimal)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 85 { return Color(red: 0.42, green: 0.87, blue: 0.44) }
        if score >= 60 { return Color(red: 0.97, green: 0.82, blue: 0.35) }
        return Color(red: 0.94, green: 0.32, blue: 0.28)
    }
}

private struct RatingsPill<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
    }
}

private struct IMDbMark: View {
    var body: some View {
        Canvas { context, size in
            // Scale to fit in 16pt height (4x ratio from 289.83)
            let scale = 16.0 / 289.83

            context.scaleBy(x: scale, y: scale)

            // Background
            var bgPath = Path()
            bgPath.move(to: CGPoint(x: 575, y: 24.91))
            bgPath.addCurve(to: CGPoint(x: 551.91, y: 0), control1: CGPoint(x: 573.44, y: 12.15), control2: CGPoint(x: 563.97, y: 1.98))
            bgPath.addLine(to: CGPoint(x: 23.32, y: 0))
            bgPath.addCurve(to: CGPoint(x: 0, y: 28.61), control1: CGPoint(x: 10.11, y: 2.17), control2: CGPoint(x: 0, y: 14.16))
            bgPath.addLine(to: CGPoint(x: 0, y: 260.86))
            bgPath.addCurve(to: CGPoint(x: 27.64, y: 289.83), control1: CGPoint(x: 0, y: 276.86), control2: CGPoint(x: 12.37, y: 289.83))
            bgPath.addLine(to: CGPoint(x: 547.59, y: 289.83))
            bgPath.addCurve(to: CGPoint(x: 575, y: 264.57), control1: CGPoint(x: 561.65, y: 289.83), control2: CGPoint(x: 573.26, y: 278.82))
            bgPath.addLine(to: CGPoint(x: 575, y: 24.91))
            bgPath.closeSubpath()
            context.fill(bgPath, with: .color(Color(red: 0.965, green: 0.78, blue: 0.0)))

            // I letter
            var iPath = Path()
            iPath.addRect(CGRect(x: 69.35, y: 58.24, width: 45.63, height: 175.65))
            context.fill(iPath, with: .color(.black))

            // M letter
            var mPath = Path()
            mPath.move(to: CGPoint(x: 201.2, y: 139.15))
            mPath.addCurve(to: CGPoint(x: 194.67, y: 94.53), control1: CGPoint(x: 197.28, y: 112.38), control2: CGPoint(x: 195.1, y: 97.5))
            mPath.addCurve(to: CGPoint(x: 189.2, y: 57.09), control1: CGPoint(x: 192.76, y: 80.2), control2: CGPoint(x: 190.94, y: 67.73))
            mPath.addLine(to: CGPoint(x: 130.04, y: 57.09))
            mPath.addLine(to: CGPoint(x: 130.04, y: 232.74))
            mPath.addLine(to: CGPoint(x: 170.01, y: 232.74))
            mPath.addLine(to: CGPoint(x: 170.15, y: 116.76))
            mPath.addLine(to: CGPoint(x: 186.97, y: 232.74))
            mPath.addLine(to: CGPoint(x: 215.44, y: 232.74))
            mPath.addLine(to: CGPoint(x: 231.39, y: 114.18))
            mPath.addLine(to: CGPoint(x: 231.54, y: 232.74))
            mPath.addLine(to: CGPoint(x: 271.38, y: 232.74))
            mPath.addLine(to: CGPoint(x: 271.38, y: 57.09))
            mPath.addLine(to: CGPoint(x: 211.77, y: 57.09))
            mPath.addLine(to: CGPoint(x: 201.2, y: 139.15))
            mPath.closeSubpath()
            context.fill(mPath, with: .color(.black))

            // D letter (simplified)
            var dPath = Path()
            dPath.addRect(CGRect(x: 287.5, y: 57.09, width: 55.28, height: 175.65))
            dPath.addEllipse(in: CGRect(x: 333.09, y: 87.13, width: 58.05, height: 115.3))
            context.fill(dPath, with: .color(.black), style: FillStyle(eoFill: true))

            // b letter (simplified)
            var bPath = Path()
            bPath.addRect(CGRect(x: 406.68, y: 55.56, width: 43.96, height: 175.65))
            bPath.addEllipse(in: CGRect(x: 450.64, y: 125.63, width: 59.41, height: 82.47))
            context.fill(bPath, with: .color(.black), style: FillStyle(eoFill: true))
        }
        .frame(width: 32, height: 16)
    }
}

private struct TomatoIcon: View {
    let score: Int

    var body: some View {
        if score >= 60 {
            // Fresh tomato
            Canvas { context, size in
                let scale = 16.0 / 48.0
                context.scaleBy(x: scale, y: scale)

                // Tomato body
                var tomatoPath = Path()
                tomatoPath.move(to: CGPoint(x: 40.9963, y: 25.4551))
                tomatoPath.addCurve(to: CGPoint(x: 33.6705, y: 13.5769), control1: CGPoint(x: 40.6543, y: 19.9723), control2: CGPoint(x: 37.866, y: 15.8702))
                tomatoPath.addLine(to: CGPoint(x: 33.44, y: 13.8184))
                tomatoPath.addCurve(to: CGPoint(x: 22.7873, y: 14.4685), control1: CGPoint(x: 30.6959, y: 12.6179), control2: CGPoint(x: 26.0405, y: 16.503))
                tomatoPath.addCurve(to: CGPoint(x: 17.6518, y: 18.967), control1: CGPoint(x: 22.8118, y: 15.1986), control2: CGPoint(x: 22.6692, y: 18.7604))
                tomatoPath.addLine(to: CGPoint(x: 17.5431, y: 18.7652))
                tomatoPath.addCurve(to: CGPoint(x: 17.9174, y: 15.0293), control1: CGPoint(x: 18.2141, y: 17.9999), control2: CGPoint(x: 18.8916, y: 16.0623))
                tomatoPath.addCurve(to: CGPoint(x: 10.6199, y: 16.6738), control1: CGPoint(x: 15.8313, y: 16.8986), control2: CGPoint(x: 14.6198, y: 17.6022))
                tomatoPath.addCurve(to: CGPoint(x: 6.89259, y: 27.5823), control1: CGPoint(x: 8.0589, y: 19.3516), control2: CGPoint(x: 6.60771, y: 23.0167))
                tomatoPath.addCurve(to: CGPoint(x: 24.9949, y: 41.6813), control1: CGPoint(x: 7.47383, y: 36.9024), control2: CGPoint(x: 16.2037, y: 42.2299))
                tomatoPath.addCurve(to: CGPoint(x: 40.9963, y: 25.4551), control1: CGPoint(x: 33.7854, y: 41.1332), control2: CGPoint(x: 41.5777, y: 34.7752))
                tomatoPath.closeSubpath()
                context.fill(tomatoPath, with: .color(Color(red: 0.98, green: 0.196, blue: 0.039)))

                // Stem/leaf
                var stemPath = Path()
                stemPath.move(to: CGPoint(x: 24.975, y: 11.3394))
                stemPath.addCurve(to: CGPoint(x: 33.6419, y: 13.5058), control1: CGPoint(x: 26.7814, y: 10.9089), control2: CGPoint(x: 31.9772, y: 11.2975))
                stemPath.addLine(to: CGPoint(x: 33.44, y: 13.8185))
                stemPath.addCurve(to: CGPoint(x: 22.7873, y: 14.4686), control1: CGPoint(x: 30.6958, y: 12.618), control2: CGPoint(x: 26.0405, y: 16.503))
                stemPath.addCurve(to: CGPoint(x: 17.6518, y: 18.9671), control1: CGPoint(x: 22.8117, y: 15.1987), control2: CGPoint(x: 22.6691, y: 18.7605))
                stemPath.addLine(to: CGPoint(x: 17.5431, y: 18.7653))
                stemPath.addCurve(to: CGPoint(x: 17.9174, y: 15.0294), control1: CGPoint(x: 18.2141, y: 18), control2: CGPoint(x: 18.8914, y: 16.0623))
                stemPath.addCurve(to: CGPoint(x: 9.48091, y: 16.3869), control1: CGPoint(x: 15.645, y: 17.0657), control2: CGPoint(x: 14.4131, y: 17.7201))
                stemPath.addLine(to: CGPoint(x: 9.54625, y: 16.0185))
                stemPath.addCurve(to: CGPoint(x: 14.5883, y: 13.4141), control1: CGPoint(x: 10.4784, y: 15.6622), control2: CGPoint(x: 12.5903, y: 14.1019))
                stemPath.addCurve(to: CGPoint(x: 15.718, y: 13.1227), control1: CGPoint(x: 14.9687, y: 13.2833), control2: CGPoint(x: 15.3479, y: 13.1817))
                stemPath.addCurve(to: CGPoint(x: 11.1272, y: 12.8312), control1: CGPoint(x: 13.5181, y: 12.9261), control2: CGPoint(x: 12.5265, y: 12.6202))
                stemPath.addLine(to: CGPoint(x: 10.9648, y: 12.5534))
                stemPath.addCurve(to: CGPoint(x: 18.4658, y: 10.6817), control1: CGPoint(x: 12.85, y: 10.125), control2: CGPoint(x: 16.323, y: 9.39163))
                stemPath.addCurve(to: CGPoint(x: 16.1104, y: 7.73988), control1: CGPoint(x: 17.145, y: 9.04509), control2: CGPoint(x: 16.1104, y: 7.73988))
                stemPath.addLine(to: CGPoint(x: 18.5619, y: 6.34741))
                stemPath.addCurve(to: CGPoint(x: 20.3117, y: 10.2572), control1: CGPoint(x: 19.5747, y: 8.61027), control2: CGPoint(x: 18.5619, y: 6.34741))
                stemPath.addCurve(to: CGPoint(x: 26.9618, y: 9.22579), control1: CGPoint(x: 22.1353, y: 7.56272), control2: CGPoint(x: 25.5282, y: 7.31403))
                stemPath.addLine(to: CGPoint(x: 26.8159, y: 9.49758))
                stemPath.addCurve(to: CGPoint(x: 24.958, y: 11.3375), control1: CGPoint(x: 25.6492, y: 9.46918), control2: CGPoint(x: 25.0067, y: 10.5304))
                stemPath.addLine(to: CGPoint(x: 24.975, y: 11.3394))
                stemPath.closeSubpath()
                context.fill(stemPath, with: .color(Color(red: 0, green: 0.569, blue: 0.176)))
            }
            .frame(width: 16, height: 16)
        } else {
            // Rotten tomato
            Canvas { context, size in
                let scale = 16.0 / 48.0
                context.scaleBy(x: scale, y: scale)

                var rottenPath = Path()
                rottenPath.move(to: CGPoint(x: 38.1588, y: 38.1158))
                rottenPath.addCurve(to: CGPoint(x: 27.2966, y: 30.7439), control1: CGPoint(x: 31.3557, y: 38.473), control2: CGPoint(x: 29.9656, y: 30.6884))
                rottenPath.addCurve(to: CGPoint(x: 25.6565, y: 33.3426), control1: CGPoint(x: 26.1592, y: 30.7677), control2: CGPoint(x: 25.2629, y: 31.9568))
                rottenPath.addCurve(to: CGPoint(x: 26.8518, y: 35.9151), control1: CGPoint(x: 25.873, y: 34.1045), control2: CGPoint(x: 26.4735, y: 35.2218))
                rottenPath.addCurve(to: CGPoint(x: 23.9047, y: 41.3645), control1: CGPoint(x: 28.1863, y: 38.3616), control2: CGPoint(x: 26.2134, y: 41.1303))
                rottenPath.addCurve(to: CGPoint(x: 18.5666, y: 37.2496), control1: CGPoint(x: 20.068, y: 41.7537), control2: CGPoint(x: 18.4676, y: 39.528))
                rottenPath.addCurve(to: CGPoint(x: 18.6223, y: 30.9663), control1: CGPoint(x: 18.6779, y: 34.6919), control2: CGPoint(x: 20.8466, y: 32.0784))
                rottenPath.addCurve(to: CGPoint(x: 12.1658, y: 35.3754), control1: CGPoint(x: 16.2913, y: 29.8009), control2: CGPoint(x: 14.3964, y: 34.3582))
                rottenPath.addCurve(to: CGPoint(x: 6.34819, y: 33.3404), control1: CGPoint(x: 10.147, y: 36.2961), control2: CGPoint(x: 7.34451, y: 35.5822))
                rottenPath.addCurve(to: CGPoint(x: 8.8914, y: 27.5744), control1: CGPoint(x: 5.6484, y: 31.7651), control2: CGPoint(x: 5.77566, y: 28.7318))
                rottenPath.addCurve(to: CGPoint(x: 15.3971, y: 26.4068), control1: CGPoint(x: 10.8376, y: 26.8516), control2: CGPoint(x: 15.1747, y: 28.5198))
                rottenPath.addCurve(to: CGPoint(x: 9.39193, y: 23.1816), control1: CGPoint(x: 15.6536, y: 23.9711), control2: CGPoint(x: 10.8409, y: 23.7657))
                rottenPath.addCurve(to: CGPoint(x: 6.5004, y: 17.5655), control1: CGPoint(x: 6.82803, y: 22.1484), control2: CGPoint(x: 5.31477, y: 19.9374))
                rottenPath.addCurve(to: CGPoint(x: 12.0052, y: 15.8418), control1: CGPoint(x: 7.38998, y: 15.7863), control2: CGPoint(x: 10.0074, y: 15.0624))
                rottenPath.addCurve(to: CGPoint(x: 16.009, y: 20.2901), control1: CGPoint(x: 14.3986, y: 16.7754), control2: CGPoint(x: 14.7828, y: 19.2578))
                rottenPath.addCurve(to: CGPoint(x: 19.4565, y: 20.6795), control1: CGPoint(x: 17.0653, y: 21.1799), control2: CGPoint(x: 18.511, y: 21.2912))
                rottenPath.addCurve(to: CGPoint(x: 20.1228, y: 18.3318), control1: CGPoint(x: 20.1537, y: 20.2282), control2: CGPoint(x: 20.3858, y: 19.2371))
                rottenPath.addCurve(to: CGPoint(x: 17.9443, y: 15.645), control1: CGPoint(x: 19.7738, y: 17.1299), control2: CGPoint(x: 18.8478, y: 16.3799))
                rottenPath.addCurve(to: CGPoint(x: 15.4396, y: 9.64644), control1: CGPoint(x: 16.3365, y: 14.338), control2: CGPoint(x: 14.0666, y: 13.2141))
                rottenPath.addCurve(to: CGPoint(x: 19.866, y: 6.61739), control1: CGPoint(x: 16.5651, y: 6.7227), control2: CGPoint(x: 19.866, y: 6.61739))
                rottenPath.addCurve(to: CGPoint(x: 23.3089, y: 7.72091), control1: CGPoint(x: 21.1775, y: 6.46991), control2: CGPoint(x: 22.3519, y: 6.86591))
                rottenPath.addCurve(to: CGPoint(x: 24.6234, y: 12.0216), control1: CGPoint(x: 24.5883, y: 8.86391), control2: CGPoint(x: 24.8375, y: 10.3917))
                rottenPath.addCurve(to: CGPoint(x: 23.6266, y: 16.2867), control1: CGPoint(x: 24.4278, y: 13.5095), control2: CGPoint(x: 23.9012, y: 14.8126))
                rottenPath.addCurve(to: CGPoint(x: 25.9622, y: 19.7898), control1: CGPoint(x: 23.308, y: 17.9981), control2: CGPoint(x: 24.2227, y: 19.7226))
                rottenPath.addCurve(to: CGPoint(x: 29.2162, y: 17.0048), control1: CGPoint(x: 28.2502, y: 19.8782), control2: CGPoint(x: 28.9363, y: 18.1195))
                rottenPath.addCurve(to: CGPoint(x: 31.6778, y: 12.9059), control1: CGPoint(x: 29.6261, y: 15.3738), control2: CGPoint(x: 30.1641, y: 13.8595))
                rottenPath.addCurve(to: CGPoint(x: 38.268, y: 14.4678), control1: CGPoint(x: 33.8503, y: 11.5371), control2: CGPoint(x: 36.868, y: 11.8371))
                rottenPath.addCurve(to: CGPoint(x: 37.3211, y: 20.9795), control1: CGPoint(x: 39.3755, y: 16.5493), control2: CGPoint(x: 39.0199, y: 19.4148))
                rottenPath.addCurve(to: CGPoint(x: 34.6513, y: 21.9357), control1: CGPoint(x: 36.559, y: 21.6813), control2: CGPoint(x: 35.6426, y: 21.9288))
                rottenPath.addCurve(to: CGPoint(x: 30.4893, y: 22.5761), control1: CGPoint(x: 33.2298, y: 21.9458), control2: CGPoint(x: 31.8089, y: 21.9109))
                rottenPath.addCurve(to: CGPoint(x: 29.1998, y: 24.7552), control1: CGPoint(x: 29.5911, y: 23.0288), control2: CGPoint(x: 29.1997, y: 23.7665))
                rottenPath.addCurve(to: CGPoint(x: 30.5143, y: 26.7578), control1: CGPoint(x: 29.1998, y: 25.7189), control2: CGPoint(x: 29.7015, y: 26.3482))
                rottenPath.addCurve(to: CGPoint(x: 35.389, y: 27.9768), control1: CGPoint(x: 32.0452, y: 27.5294), control2: CGPoint(x: 33.7352, y: 27.6872))
                rottenPath.addCurve(to: CGPoint(x: 41.2497, y: 31.467), control1: CGPoint(x: 37.7872, y: 28.3968), control2: CGPoint(x: 39.8959, y: 29.2415))
                rottenPath.addLine(to: CGPoint(x: 41.2852, y: 31.5262))
                rottenPath.addCurve(to: CGPoint(x: 38.1588, y: 38.1158), control1: CGPoint(x: 42.84, y: 34.1612), control2: CGPoint(x: 41.214, y: 37.9552))
                rottenPath.closeSubpath()
                context.fill(rottenPath, with: .color(Color(red: 0.039, green: 0.784, blue: 0.333)))
            }
            .frame(width: 16, height: 16)
        }
    }
}

private struct PopcornIcon: View {
    let score: Int

    var body: some View {
        Image(systemName: score >= 60 ? "popcorn.fill" : "popcorn")
            .foregroundStyle(score >= 60 ? Color(red: 0.98, green: 0.196, blue: 0.039) : Color(red: 0.039, green: 0.784, blue: 0.333))
            .font(.system(size: 14))
            .frame(width: 16, height: 16)
    }
}

private struct TechnicalDetailsSection: View {
    let version: DetailsViewModel.VersionDetail
    let layout: DetailsLayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsSectionHeader(title: "Technical Details")

            // Main technical specs grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.technicalGridMinimum), spacing: 16)], spacing: 16) {
                ForEach(technicalPairs(), id: \.0) { pair in
                    TechnicalInfoTile(label: pair.0, value: pair.1)
                }
            }

            // Audio & Subtitle tracks
            if !version.audioTracks.isEmpty || !version.subtitleTracks.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    if !version.audioTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Audio Tracks")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                            FlowChipGroup(texts: version.audioTracks.map { $0.name })
                        }
                    }
                    if !version.subtitleTracks.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Subtitles")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .textCase(.uppercase)
                            FlowChipGroup(texts: version.subtitleTracks.map { $0.name })
                        }
                    }
                }
            }
        }
    }

    private func technicalPairs() -> [(String, String)] {
        var list: [(String, String)] = []
        list.append(("Version", version.label))
        if let reso = version.technical.resolution { list.append(("Resolution", reso)) }
        if let video = version.technical.videoCodec { list.append(("Video", video.uppercased())) }
        if let profile = version.technical.videoProfile, !profile.isEmpty { list.append(("Profile", profile.uppercased())) }
        if let audio = version.technical.audioCodec { list.append(("Audio", audio.uppercased())) }
        if let channels = version.technical.audioChannels { list.append(("Channels", "\(channels)")) }
        if let bitrate = version.technical.bitrate {
            let mbps = Double(bitrate) / 1000.0
            list.append(("Bitrate", String(format: "%.1f Mbps", mbps)))
        }
        if let size = version.technical.fileSizeMB {
            if size >= 1024 {
                list.append(("File Size", String(format: "%.2f GB", size / 1024.0)))
            } else {
                list.append(("File Size", String(format: "%.0f MB", size)))
            }
        }
        if let runtime = version.technical.durationMin {
            list.append(("Runtime", "\(runtime)m"))
        }
        if let subs = version.technical.subtitleCount, subs > 0 {
            list.append(("Subtitles", "\(subs)"))
        }
        return list
    }
}

private struct CastCrewSection: View {
    let cast: [DetailsViewModel.Person]
    let crew: [DetailsViewModel.CrewPerson]
    let layout: DetailsLayoutMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailsSectionHeader(title: "Cast & Crew")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: layout.castGridMinimum), spacing: 20)], spacing: 24) {
                ForEach(Array(people.prefix(15))) { person in
                    CastCrewCard(person: person)
                }
            }
        }
    }

    private var people: [CastCrewCard.Person] {
        var seen = Set<String>()
        var combined: [CastCrewCard.Person] = []
        for c in cast {
            if seen.insert(c.id).inserted {
                combined.append(CastCrewCard.Person(id: c.id, name: c.name, role: nil, image: c.profile))
            }
        }
        for m in crew {
            if seen.insert(m.id).inserted {
                combined.append(CastCrewCard.Person(id: m.id, name: m.name, role: m.job, image: m.profile))
            }
        }
        return combined
    }
}

private struct CastCrewCard: View, Identifiable {
    struct Person: Identifiable {
        let id: String
        let name: String
        let role: String?
        let image: URL?
    }

    let person: Person
    var id: String { person.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Profile Image
            ZStack {
                if let imageURL = person.image {
                    CachedAsyncImage(url: imageURL)
                        .aspectRatio(2/3, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    // Placeholder for missing image
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .aspectRatio(2/3, contentMode: .fit)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white.opacity(0.25))
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

            // Name & Role
            VStack(alignment: .leading, spacing: 3) {
                Text(person.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.white.opacity(0.95))
                if let role = person.role, !role.isEmpty {
                    Text(role)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct TechnicalInfoTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}

private struct DetailsSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white.opacity(0.95))
    }
}

private struct FlowChipGroup: View {
    let texts: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(texts, id: \.self) { text in
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    )
            }
        }
    }
}

private struct Badge: View { let text: String; var body: some View { Text(text).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(Color.white.opacity(0.12)).cornerRadius(6) } }

// MARK: - Collapsible Overview Component

private struct CollapsibleOverview: View {
    let text: String
    let maxWidth: CGFloat
    @Binding var isExpanded: Bool

    @State private var intrinsicHeight: CGFloat = 0
    @State private var truncatedHeight: CGFloat = 0

    private var isTruncated: Bool {
        intrinsicHeight > truncatedHeight && truncatedHeight > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(4)
                .lineLimit(isExpanded ? nil : 2)
                .frame(maxWidth: maxWidth, alignment: .leading)
                .multilineTextAlignment(.leading)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TruncatedHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                )
                .onPreferenceChange(TruncatedHeightPreferenceKey.self) { height in
                    if !isExpanded {
                        truncatedHeight = height
                    }
                }
                .background(
                    // Hidden text without line limit to get intrinsic height
                    Text(text)
                        .font(.system(size: 16))
                        .lineSpacing(4)
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: IntrinsicHeightPreferenceKey.self,
                                    value: geometry.size.height
                                )
                            }
                        )
                        .onPreferenceChange(IntrinsicHeightPreferenceKey.self) { height in
                            intrinsicHeight = height
                        }
                )

            if isTruncated {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(isExpanded ? "Less" : "More")
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: maxWidth, alignment: .leading)
            }
        }
    }
}

private struct TruncatedHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct IntrinsicHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#if DEBUG && canImport(PreviewsMacros)
#Preview {
    DetailsView(item: MediaItem(
        id: "plex:1",
        title: "Sample Title",
        type: "movie",
        thumb: nil,
        art: nil,
        year: 2024,
        rating: 8.1,
        duration: 7200000,
        viewOffset: nil,
        summary: "A minimal details preview",
        grandparentTitle: nil,
        grandparentThumb: nil,
        grandparentArt: nil,
        parentIndex: nil,
        index: nil
    ))
}
#endif
