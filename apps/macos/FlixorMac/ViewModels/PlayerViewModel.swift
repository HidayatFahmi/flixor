//
//  PlayerViewModel.swift
//  FlixorMac
//
//  Video player view model with AVPlayer integration
//

import Foundation
import AVKit
import SwiftUI
import Combine

@MainActor
class PlayerViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isLoading = true
    @Published var error: String?
    @Published var volume: Float = 1.0
    @Published var isMuted = false
    @Published var isFullScreen = false

    // Stream info
    @Published var streamURL: URL?
    @Published var availableQualities: [String] = []
    @Published var selectedQuality: String = "Original"

    // Playback metadata
    let item: MediaItem
    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var kvoCancellables = Set<AnyCancellable>()
    private let api = APIClient.shared

    // Progress tracking
    private var progressTimer: Timer?
    private var lastReportedProgress: TimeInterval = 0
    private var initialSeekApplied = false
    private var serverResumeSeconds: TimeInterval?

    // Session tracking for cleanup
    private var sessionId: String?
    private var plexBaseUrl: String?
    private var plexToken: String?
    private var currentURLIsHLS: Bool = false

    init(item: MediaItem) {
        self.item = item
        setupPlayer()
    }

    deinit {
        // Cleanup synchronously in deinit
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        progressTimer?.invalidate()
        progressTimer = nil
        player?.pause()
        player = nil
        cancellables.removeAll()
        print("🧹 [Player] Cleaned up")
    }

    // MARK: - Player Setup

    private func setupPlayer() {
        Task {
            await fetchServerResumeOffset()
            await loadStreamURL()
        }
    }

    private func fetchServerResumeOffset() async {
        // Try to get latest playstate from backend metadata if not included
        let rk = item.id.replacingOccurrences(of: "plex:", with: "")
        guard !rk.isEmpty else { return }
        do {
            struct Meta: Decodable { let viewOffset: Int? }
            let meta: Meta = try await api.get("/api/plex/metadata/\(rk)")
            if let ms = meta.viewOffset, ms > 2000 {
                serverResumeSeconds = TimeInterval(ms) / 1000.0
                print("🕑 [Player] Server resume offset: \(ms) ms")
            }
        } catch {
            print("⚠️ [Player] Failed to fetch server resume offset: \(error)")
        }
    }

    private func loadStreamURL() async {
        isLoading = true
        error = nil

        do {
            // Extract ratingKey from item.id
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")

            guard !ratingKey.isEmpty else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid item ID: \(item.id)"])
            }

            print("📺 [Player] Fetching stream URL for ratingKey: \(ratingKey)")
            print("📺 [Player] Item title: \(item.title)")

            // Get Plex server connection details (like mobile app)
            let servers = try await api.getPlexServers()
            guard let activeServer = servers.first(where: { $0.isActive == true }) else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No active Plex server configured"])
            }

            print("📺 [Player] Using server: \(activeServer.name)")

            let connectionsResponse = try await api.getPlexConnections(serverId: activeServer.id)
            let connections = connectionsResponse.connections

            // Prefer local connection, fall back to first available
            guard let selectedConnection = connections.first(where: { $0.local == true }) ?? connections.first else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No Plex server connection available"])
            }

            let baseUrl = selectedConnection.uri.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            print("📺 [Player] Server URL: \(baseUrl)")

            // Store for cleanup
            self.plexBaseUrl = baseUrl

            // Get Plex access token
            let authServers = try await api.getPlexAuthServers()
            guard let serverWithToken = authServers.first(where: {
                $0.clientIdentifier == activeServer.id ||
                $0.clientIdentifier == activeServer.machineIdentifier
            }), let token = serverWithToken.token as String? else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not get Plex access token"])
            }

            // Store for cleanup
            self.plexToken = token

            print("📺 [Player] Got access token")

            // First try: Direct Play via Plex part URL if available
            struct MetaMedia: Decodable {
                struct Part: Decodable { let key: String? }
                let Part: [Part]?
                let container: String?
                let videoCodec: String?
                let audioCodec: String?
            }
            struct MetaResponse: Decodable { let Media: [MetaMedia]? }
            var directURL: URL? = nil
            do {
                let meta: MetaResponse = try await api.get("/api/plex/metadata/\(ratingKey)")
                let m = meta.Media?.first
                // Gate direct play: avoid MKV, HEVC/Dolby Vision/TrueHD containers/codecs known to fail in AVFoundation
                let container = (m?.container ?? "").lowercased()
                let vcodec = (m?.videoCodec ?? "").lowercased()
                let acodec = (m?.audioCodec ?? "").lowercased()
                let unsafeContainer = container.contains("mkv") || container.contains("mka")
                let unsafeVideo = vcodec.contains("hevc") || vcodec.contains("dvh") || vcodec.contains("dvhe")
                let unsafeAudio = acodec.contains("truehd") || acodec.contains("eac3") // macOS often lacks passthrough
                let allowDirect = !(unsafeContainer || unsafeVideo || unsafeAudio)

                if allowDirect, let key = m?.Part?.first?.key, !key.isEmpty {
                    let direct = "\(baseUrl)\(key)?X-Plex-Token=\(token)"
                    directURL = URL(string: direct)
                    if directURL != nil { print("🎯 [Player] Attempting Direct Play: \(direct)") }
                } else {
                    if !allowDirect { print("🚫 [Player] Skipping Direct Play due to incompatible container/codec: cont=\(container), v=\(vcodec), a=\(acodec)") }
                }
            } catch {
                print("⚠️ [Player] Could not fetch metadata for direct play: \(error)")
            }

            var startURL: URL
            if let d = directURL {
                self.streamURL = d
                startURL = d
            } else {
                // Fallback: backend HLS endpoint
                print("📺 [Player] Requesting stream URL from backend (HLS)")
                struct StreamResponse: Codable { let url: String }
                let response: StreamResponse = try await api.get(
                    "/api/plex/stream/\(ratingKey)",
                    queryItems: [
                        URLQueryItem(name: "protocol", value: "hls"),
                        URLQueryItem(name: "directPlay", value: "0"),
                        URLQueryItem(name: "directStream", value: "0"),
                        URLQueryItem(name: "autoAdjustQuality", value: "0"),
                        URLQueryItem(name: "maxVideoBitrate", value: "20000"),
                        URLQueryItem(name: "videoCodec", value: "h264"),
                        URLQueryItem(name: "audioCodec", value: "aac"),
                        URLQueryItem(name: "container", value: "mpegts")
                    ]
                )
                print("📺 [Player] Received stream URL: \(response.url)")
                guard let u = URL(string: response.url) else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid stream URL"])
                }
                startURL = u
                self.currentURLIsHLS = true
            }

            // The start.m3u8 URL needs to be called to initiate the session
            // Then we use the session-based URL for actual playback
            if startURL.absoluteString.contains("start.m3u8") {
                print("📺 [Player] Starting transcode session")

                // Extract session ID from URL
                if let sessionParam = URLComponents(string: startURL.absoluteString)?.queryItems?.first(where: { $0.name == "session" })?.value {
                    self.sessionId = sessionParam
                }

                // Start the session by fetching the start URL
                let (_, startResponse) = try await URLSession.shared.data(from: startURL)
                if let httpResponse = startResponse as? HTTPURLResponse {
                    print("📺 [Player] Start response: \(httpResponse.statusCode)")
                }

                // Wait for session to initialize
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                // Build session URL
                guard let sessionId = self.sessionId,
                      let baseUrlString = startURL.absoluteString.components(separatedBy: "/video/").first,
                      let token = URLComponents(string: startURL.absoluteString)?.queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to extract session info"])
                }

                let sessionURL = "\(baseUrlString)/video/:/transcode/universal/session/\(sessionId)/base/index.m3u8?X-Plex-Token=\(token)"
                guard let url = URL(string: sessionURL) else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid session URL"])
                }

                self.streamURL = url
                print("✅ [Player] Using session URL: \(sessionURL)")
            } else {
                self.streamURL = startURL
                print("✅ [Player] Stream URL ready: \(startURL.absoluteString)")
            }

            // Initialize AVPlayer
            guard let finalURL = self.streamURL else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stream URL not set"])
            }
            // Configure asset with better buffering
            let asset = AVURLAsset(url: finalURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let playerItem = AVPlayerItem(asset: asset)
            // Buffering preferences
            if currentURLIsHLS || startURL.absoluteString.contains("m3u8") {
                playerItem.preferredForwardBufferDuration = 45 // HLS: buffer more
            } else {
                playerItem.preferredForwardBufferDuration = 10 // Direct play: lighter buffer
            }
            playerItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            playerItem.preferredPeakBitRate = 0

            // Add error observer
            playerItem.publisher(for: \.error)
                .sink { [weak self] error in
                    if let error = error {
                        print("❌ [Player] AVPlayerItem error: \(error.localizedDescription)")
                        Task { @MainActor [weak self] in
                            self?.error = "Playback error: \(error.localizedDescription)"
                            self?.isLoading = false
                        }
                    }
                }
                .store(in: &cancellables)

            self.player = AVPlayer(playerItem: playerItem)
            self.player?.automaticallyWaitsToMinimizeStalling = true
            self.player?.actionAtItemEnd = .pause
            self.player?.allowsExternalPlayback = false

            // Setup observers
            setupTimeObserver()
            setupPlayerObservers(playerItem: playerItem)
            setupPlayerStateObservers()

            // Auto-play immediately
            self.player?.play()
            self.isPlaying = true

            // Start progress tracking
            startProgressTracking()

        } catch {
            print("❌ [Player] Failed to load stream: \(error)")
            self.error = "Failed to load video stream: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    // MARK: - Player Observers

    private func setupTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime = time.seconds

                // Update duration if available
                if let duration = player.currentItem?.duration.seconds, !duration.isNaN {
                    self.duration = duration
                }
            }
        }
    }

    private func setupPlayerObservers(playerItem: AVPlayerItem) {
        // Observe status
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch status {
                    case .readyToPlay:
                        print("✅ [Player] Ready to play")
                        self.isLoading = false
                        // Apply initial resume seek once when ready
                        self.applyInitialSeekIfNeeded()
                    case .failed:
                        print("❌ [Player] Failed: \(playerItem.error?.localizedDescription ?? "Unknown error")")
                        if self.currentURLIsHLS == false {
                            print("↩️ [Player] Direct play failed; falling back to HLS")
                            await self.reloadAsHLSFallback()
                        } else {
                            self.error = playerItem.error?.localizedDescription ?? "Playback failed"
                            self.isLoading = false
                        }
                    case .unknown:
                        print("⏳ [Player] Status unknown")
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("✅ [Player] Playback finished")
                    self.handlePlaybackEnd()
                }
            }
            .store(in: &cancellables)

        // Observe stalls
        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: playerItem)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("⚠️ [Player] Playback stalled")
                    self.isLoading = true
                    if let it = self.player?.currentItem {
                        it.preferredForwardBufferDuration = max(30, it.preferredForwardBufferDuration)
                    }
                    // Nudge playback
                    self.player?.pause()
                    self.player?.play()
                }
            }
            .store(in: &cancellables)

        // Observe buffering-related properties
        playerItem.publisher(for: \.isPlaybackLikelyToKeepUp)
            .sink { [weak self] keepUp in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if keepUp {
                        self.isLoading = false
                    }
                }
            }
            .store(in: &cancellables)

        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .sink { [weak self] empty in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if empty {
                        self.isLoading = true
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func setupPlayerStateObservers() {
        guard let player = player else { return }
        // Track timeControlStatus to reflect buffering/playing state
        player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    switch status {
                    case .waitingToPlayAtSpecifiedRate:
                        self.isLoading = true
                    case .playing, .paused:
                        self.isLoading = false
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &kvoCancellables)
    }

    private func reloadAsHLSFallback() async {
        // Build HLS URL and replace current item
        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct StreamResponse: Codable { let url: String }
            let response: StreamResponse = try await api.get(
                "/api/plex/stream/\(ratingKey)",
                queryItems: [
                    URLQueryItem(name: "protocol", value: "hls"),
                    URLQueryItem(name: "directPlay", value: "0"),
                    URLQueryItem(name: "directStream", value: "0"),
                    URLQueryItem(name: "autoAdjustQuality", value: "0"),
                    URLQueryItem(name: "maxVideoBitrate", value: "20000"),
                    URLQueryItem(name: "videoCodec", value: "h264"),
                    URLQueryItem(name: "audioCodec", value: "aac"),
                    URLQueryItem(name: "container", value: "mpegts")
                ]
            )
            guard let url = URL(string: response.url) else {
                throw NSError(domain: "PlayerError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid HLS URL"])
            }
            self.streamURL = url
            self.currentURLIsHLS = true

            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 45
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            item.preferredPeakBitRate = 0

            if self.player == nil { self.player = AVPlayer(playerItem: item) } else { self.player?.replaceCurrentItem(with: item) }
            self.player?.automaticallyWaitsToMinimizeStalling = true
            self.player?.allowsExternalPlayback = false

            setupPlayerObservers(playerItem: item)
            setupPlayerStateObservers()
            self.player?.play()
            self.isPlaying = true
            self.isLoading = false
        } catch {
            print("❌ [Player] HLS fallback failed: \(error)")
            self.error = "Playback failed: \(error.localizedDescription)"
            self.isLoading = false
        }
    }

    private func applyInitialSeekIfNeeded() {
        guard !initialSeekApplied else { return }
        let ms = item.viewOffset ?? 0
        var seconds = TimeInterval(ms) / 1000.0
        if (seconds <= 2), let s = serverResumeSeconds { seconds = s }
        guard seconds > 2 else { // ignore trivial offsets
            initialSeekApplied = true
            return
        }
        initialSeekApplied = true
        seek(to: seconds)
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
            stopProgressTracking()
        } else {
            player.play()
            isPlaying = true
            startProgressTracking()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player = player else { return }
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: cmTime) { [weak self] finished in
            if finished {
                print("✅ [Player] Seeked to \(time)s")
                Task { @MainActor [weak self] in
                    await self?.reportProgress()
                }
            }
        }
    }

    func skip(seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        player?.volume = isMuted ? 0 : volume
    }

    func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0 : volume
    }

    func changeQuality(_ quality: String) {
        selectedQuality = quality
        let savedTime = currentTime

        Task {
            await loadStreamURL()
            // Restore playback position
            if savedTime > 0 {
                seek(to: savedTime)
            }
        }
    }

    // MARK: - Progress Tracking

    private func startProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.reportProgress()
            }
        }
    }

    private func stopProgressTracking() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func reportProgress() async {
        guard currentTime > 0, duration > 0 else { return }

        // Only report if progress changed significantly (more than 5 seconds)
        guard abs(currentTime - lastReportedProgress) > 5 else { return }

        lastReportedProgress = currentTime

        let progressPercent = Int((currentTime / duration) * 100)
        print("📊 [Player] Progress: \(Int(currentTime))s / \(Int(duration))s (\(progressPercent)%)")

        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct ProgressRequest: Encodable {
                let ratingKey: String
                let time: Int
                let duration: Int
                let state: String
            }
            let request = ProgressRequest(
                ratingKey: ratingKey,
                time: Int(currentTime * 1000),
                duration: Int(duration * 1000),
                state: isPlaying ? "playing" : "paused"
            )
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [Player] Failed to report progress: \(error)")
        }
    }

    private func reportStopped() async {
        guard duration > 0 else { return }
        do {
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
            struct ProgressRequest: Encodable {
                let ratingKey: String
                let time: Int
                let duration: Int
                let state: String
            }
            let request = ProgressRequest(
                ratingKey: ratingKey,
                time: Int(currentTime * 1000),
                duration: Int(duration * 1000),
                state: "stopped"
            )
            let _: EmptyResponse = try await api.post("/api/plex/progress", body: request)
        } catch {
            print("⚠️ [Player] Failed to report stopped: \(error)")
        }
    }

    private func handlePlaybackEnd() {
        isPlaying = false
        stopProgressTracking()

        // Mark as watched
        Task {
            do {
                let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")
                struct ScrobbleRequest: Encodable {
                    let ratingKey: String
                }
                let _: EmptyResponse = try await api.post("/api/plex/scrobble", body: ScrobbleRequest(ratingKey: ratingKey))
                print("✅ [Player] Marked as watched")
            } catch {
                print("⚠️ [Player] Failed to mark as watched: \(error)")
            }
        }
    }

    // MARK: - Cleanup

    private func stopTranscodeSession() async {
        guard let sessionId = sessionId,
              let baseUrl = plexBaseUrl,
              let token = plexToken else {
            return
        }

        do {
            let stopUrl = "\(baseUrl)/video/:/transcode/universal/stop?session=\(sessionId)&X-Plex-Token=\(token)"
            guard let url = URL(string: stopUrl) else { return }

            print("🛑 [Player] Stopping transcode session: \(sessionId)")
            _ = try await URLSession.shared.data(from: url)
            print("✅ [Player] Transcode session stopped")
        } catch {
            print("⚠️ [Player] Failed to stop transcode session: \(error)")
        }
    }

    func onDisappear() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.reportProgress() // Final progress snapshot
            await self.reportStopped()  // Explicit stopped state like web

            // Stop the transcode session
            await self.stopTranscodeSession()

            if let observer = self.timeObserver {
                self.player?.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            self.stopProgressTracking()
            self.player?.pause()
            self.player = nil
            self.cancellables.removeAll()
        }
    }
}

// MARK: - Helper Response Types

struct EmptyResponse: Codable {}
