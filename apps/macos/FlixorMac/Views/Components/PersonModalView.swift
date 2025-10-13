//
//  PersonModalView.swift
//  FlixorMac
//
//  Displays cast/crew filmography using glassmorphic modal styling.
//

import SwiftUI

struct PersonReference: Identifiable {
    let id: String
    let name: String
    let role: String?
    let image: URL?
}

struct PersonModalView: View {
    @Binding var isPresented: Bool
    var person: PersonReference?
    @ObservedObject var viewModel: PersonModalViewModel
    var onSelect: (MediaItem) -> Void

    private let cardWidth: CGFloat = 420

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            GeometryReader { proxy in
                let width = min(proxy.size.width - 160, 960)
                let height = min(proxy.size.height - 260, max(proxy.size.height * 0.7, 700))

                VStack(spacing: 0) {
                    header
                    Divider()
                        .background(Color.white.opacity(0.08))
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                }
                .frame(width: width, height: height, alignment: .top)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.95))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 32, x: 0, y: 24)
                .padding(.horizontal, max(0, (proxy.size.width - width) / 2))
            }
            .padding(.vertical, 40)
        }
        .transition(.opacity.combined(with: .scale))
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(spacing: 16) {
            let profileURL = viewModel.profileURL ?? person?.image

            if let url = profileURL {
                CachedAsyncImage(url: url, aspectRatio: 0.75, contentMode: .fill)
                    .offset(y:10)
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.6))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                let fallbackName = person?.name ?? "Cast Member"
                Text(viewModel.name.isEmpty ? fallbackName : viewModel.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                } else if let role = person?.role, !role.isEmpty {
                    Text(role)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.18))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            BrowseSkeletonGrid(cardWidth: cardWidth)
        } else if let error = viewModel.error {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Button("Retry") {
                    Task {
                        await viewModel.load(personId: person?.id, name: person?.name ?? viewModel.name, profilePath: person?.image ?? viewModel.profileURL)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.movies.isEmpty && viewModel.shows.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "film")
                    .font(.system(size: 42))
                    .foregroundStyle(.white.opacity(0.6))
                Text("No credits found.")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !viewModel.movies.isEmpty {
                        carouselSection(title: "Movies", items: viewModel.movies, isLoadingMore: viewModel.isLoadingMoreMovies) { item in
                            await viewModel.loadMoreMoviesIfNeeded(currentItem: item)
                        }
                    }
                    if !viewModel.shows.isEmpty {
                        carouselSection(title: "TV Shows", items: viewModel.shows, isLoadingMore: viewModel.isLoadingMoreShows) { item in
                            await viewModel.loadMoreShowsIfNeeded(currentItem: item)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func carouselSection(title: String, items: [MediaItem], isLoadingMore: Bool, loadMore: @escaping (MediaItem) async -> Void) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            CarouselRow(
                title: title,
                items: items,
                itemWidth: cardWidth,
                spacing: 16,
                rowHeight: (cardWidth * 0.5) + 56
            ) { item in
                LandscapeCard(item: item, width: cardWidth) {
                    dismiss()
                    onSelect(item)
                }
                .onAppear {
                    Task { await loadMore(item) }
                }
            }

            if isLoadingMore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
