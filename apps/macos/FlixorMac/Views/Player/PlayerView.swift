//
//  PlayerView.swift
//  FlixorMac
//
//  Video player with AVPlayer and custom controls
//

import SwiftUI
import AVKit

struct PlayerView: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isFullScreen = false

    init(item: MediaItem) {
        self.item = item
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video Player
            if let player = viewModel.player {
                VideoPlayerView(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleControls()
                    }
            }

            // Loading Indicator
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }

            // Error State
            if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("Playback Error")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text(error)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Close") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            // Controls Overlay
            if showControls && !viewModel.isLoading && viewModel.error == nil {
                PlayerControlsView(
                    viewModel: viewModel,
                    isFullScreen: $isFullScreen,
                    onClose: {
                        dismiss()
                    },
                    onToggleFullScreen: toggleFullScreen
                )
                .transition(.opacity)
            }
        }
        .onAppear {
            scheduleHideControls()
        }
        .onDisappear {
            viewModel.onDisappear()
            // Exit fullscreen when leaving player
            if isFullScreen {
                toggleFullScreen()
            }
        }
        .onHover { hovering in
            if hovering {
                showControls = true
                scheduleHideControls()
            }
        }
    }

    private func toggleFullScreen() {
        #if os(macOS)
        if let window = NSApp.keyWindow {
            window.toggleFullScreen(nil)
            isFullScreen.toggle()
        }
        #endif
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
            if !Task.isCancelled && viewModel.isPlaying {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Video Player View (AVPlayerLayer wrapper)

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = PlayerContainerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let playerView = nsView as? PlayerContainerView {
            playerView.player = player
        }
    }

    class PlayerContainerView: NSView {
        private var playerLayer: AVPlayerLayer?

        var player: AVPlayer? {
            didSet {
                setupPlayerLayer()
            }
        }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private func setupPlayerLayer() {
            playerLayer?.removeFromSuperlayer()

            guard let player = player else { return }

            let newPlayerLayer = AVPlayerLayer(player: player)
            newPlayerLayer.frame = bounds
            newPlayerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(newPlayerLayer)
            playerLayer = newPlayerLayer
        }

        override func layout() {
            super.layout()
            playerLayer?.frame = bounds
        }
    }
}

// MARK: - Player Controls

struct PlayerControlsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Binding var isFullScreen: Bool
    let onClose: () -> Void
    let onToggleFullScreen: () -> Void

    @State private var isDraggingTimeline = false
    @State private var draggedTime: TimeInterval = 0

    var body: some View {
        VStack {
            // Top Bar
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(viewModel.item.title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Spacer()

                // Quality Selector (if available)
                if !viewModel.availableQualities.isEmpty {
                    Menu {
                        ForEach(viewModel.availableQualities, id: \.self) { quality in
                            Button(quality) {
                                viewModel.changeQuality(quality)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(viewModel.selectedQuality)
                            Image(systemName: "chevron.down")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            // Bottom Controls
            VStack(spacing: 12) {
                // Timeline
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            Rectangle()
                                .fill(Color.white.opacity(0.3))
                                .frame(height: 4)

                            // Progress
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geometry.size.width * CGFloat(currentProgress), height: 4)

                            // Scrubber
                            Circle()
                                .fill(Color.white)
                                .frame(width: 12, height: 12)
                                .offset(x: geometry.size.width * CGFloat(currentProgress) - 6)
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDraggingTimeline = true
                                    let progress = min(max(0, value.location.x / geometry.size.width), 1)
                                    draggedTime = viewModel.duration * progress
                                }
                                .onEnded { value in
                                    isDraggingTimeline = false
                                    viewModel.seek(to: draggedTime)
                                }
                        )
                    }
                    .frame(height: 12)

                    // Time Labels
                    HStack {
                        Text(formatTime(isDraggingTimeline ? draggedTime : viewModel.currentTime))
                            .font(.caption)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(formatTime(viewModel.duration))
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 20)

                // Play/Pause & Volume
                HStack(spacing: 20) {
                    // Skip back
                    Button(action: { viewModel.skip(seconds: -10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    // Play/Pause
                    Button(action: { viewModel.togglePlayPause() }) {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Skip forward
                    Button(action: { viewModel.skip(seconds: 10) }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Volume
                    HStack(spacing: 8) {
                        Button(action: { viewModel.toggleMute() }) {
                            Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Slider(value: Binding(
                            get: { viewModel.volume },
                            set: { viewModel.setVolume($0) }
                        ), in: 0...1)
                        .frame(width: 100)
                        .tint(.white)
                    }

                    // Fullscreen button
                    Button(action: onToggleFullScreen) {
                        Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
            .background(
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 200)
            )
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.6), .clear, .clear],
                startPoint: .top,
                endPoint: .center
            )
            .frame(height: 120)
            .frame(maxHeight: .infinity, alignment: .top)
        )
    }

    private var currentProgress: Double {
        guard viewModel.duration > 0 else { return 0 }
        let time = isDraggingTimeline ? draggedTime : viewModel.currentTime
        return time / viewModel.duration
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && !seconds.isInfinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

#Preview {
    PlayerView(item: MediaItem(
        id: "plex:1",
        title: "Sample Title",
        type: "movie",
        thumb: nil,
        art: nil,
        year: 2024,
        rating: 8.1,
        duration: 7200000,
        viewOffset: nil,
        summary: "A minimal player preview",
        grandparentTitle: nil,
        grandparentThumb: nil,
        grandparentArt: nil,
        parentIndex: nil,
        index: nil
    ))
}

