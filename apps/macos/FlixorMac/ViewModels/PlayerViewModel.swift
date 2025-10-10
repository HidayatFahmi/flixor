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
    @Published var playbackSpeed: Float = 1.0

    // Stream info
    @Published var streamURL: URL?
    @Published var availableQualities: [String] = []
    @Published var selectedQuality: String = "Original"

    // Markers (intro/credits) - no high-frequency updates
    @Published var markers: [PlayerMarker] = []
    @Published var currentMarker: PlayerMarker? = nil

    // Next episode & season episodes
    @Published var nextEpisode: EpisodeMetadata? = nil
    @Published var seasonEpisodes: [EpisodeMetadata] = []
    @Published var nextEpisodeCountdown: Int? = nil

    // Playback metadata
    let item: MediaItem
    private(set) var player: AVPlayer?
    @Published var mpvController: MPVPlayerController?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var kvoCancellables = Set<AnyCancellable>()
    private let api = APIClient.shared

    // Backend selection
    private var playerBackend: PlayerBackend {
        UserDefaults.standard.playerBackend
    }

    // Progress tracking
    private var progressTimer: Timer?
    private var lastReportedProgress: TimeInterval = 0
    private var initialSeekApplied = false
    private var serverResumeSeconds: TimeInterval?

    // Countdown timer for next episode
    private var countdownTimer: Timer?

    // Session tracking for cleanup
    private var sessionId: String?
    private var plexBaseUrl: String?
    private var plexToken: String?
    private var currentURLIsHLS: Bool = false

    // Navigation callback for next episode
    var onPlayNext: ((MediaItem) -> Void)?

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

            // Initialize backend based on user preference
            switch playerBackend {
            case .avplayer:
                print("🎬 [Player] Using AVPlayer backend")
                await loadStreamURL()
            case .mpv:
                print("🎬 [Player] Using MPV backend")
                setupMPVController()
                await loadStreamURL()
            }
        }
    }

    private func setupMPVController() {
        let controller = MPVPlayerController()

        // Setup property change callback
        controller.onPropertyChange = { [weak self] property, value in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch property {
                case "time-pos":
                    if let time = value as? Double {
                        self.currentTime = time
                        // Check for markers whenever time updates (matches web/mobile frequency)
                        self.updateCurrentMarker()
                        // Update next episode countdown
                        self.updateNextEpisodeCountdown()
                    }
                case "duration":
                    if let dur = value as? Double {
                        self.duration = dur
                    }
                case "pause":
                    if let paused = value as? Bool {
                        self.isPlaying = !paused
                    }
                case "volume":
                    if let vol = value as? Double {
                        self.volume = Float(vol / 100.0)
                    }
                case "mute":
                    if let muted = value as? Bool {
                        self.isMuted = muted
                    }
                default:
                    break
                }
            }
        }

        // Setup event callback
        controller.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("🎯 [Player] MPV event: \(event)")
                switch event {
                case "file-started":
                    print("📺 [Player] MPV file started")
                case "file-loaded":
                    print("✅ [Player] MPV file loaded")
                    self.isLoading = false
                    self.applyInitialSeekIfNeeded()
                case "playback-restart":
                    print("▶️ [Player] MPV playback started")
                    self.isPlaying = true
                    self.isLoading = false
                case "file-ended":
                    print("✅ [Player] MPV playback finished")
                    self.handlePlaybackEnd()
                default:
                    print("ℹ️ [Player] MPV event (unhandled): \(event)")
                    break
                }
            }
        }

        self.mpvController = controller
        print("✅ [Player] MPV controller initialized")
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

    private func fetchMarkers(ratingKey: String) async {
        print("🎯 [Player] fetchMarkers() CALLED for ratingKey: \(ratingKey)")
        do {
            print("🌐 [Player] Calling api.getPlexMarkers...")
            let plexMarkers = try await api.getPlexMarkers(ratingKey: ratingKey)
            print("✅ [Player] Got \(plexMarkers.count) raw markers from API")
            // Map to PlayerMarker (ensure id and ms fields present)
            let mapped: [PlayerMarker] = plexMarkers.compactMap { m in
                guard let type = m.type?.lowercased(),
                      let s = m.startTimeOffset, let e = m.endTimeOffset else { return nil }
                // Only care about intro/credits
                guard type == "intro" || type == "credits" else { return nil }
                let id = m.id ?? "\(type)-\(s)-\(e)"
                return PlayerMarker(id: id, type: type, startTimeOffset: s, endTimeOffset: e)
            }
            self.markers = mapped
            print("🎬 [Player] Markers found: \(mapped.count) - \(mapped.map { "\($0.type): \($0.startTimeOffset)-\($0.endTimeOffset)" })")
        } catch {
            print("⚠️ [Player] Failed to fetch markers: \(error)")
            self.markers = []
        }
    }

    private func fetchNextEpisode(parentRatingKey: String, currentRatingKey: String) async {
        do {
            // Fetch all episodes in the season
            struct EpisodeResponse: Decodable {
                let Metadata: [EpisodeMetadata]?
            }
            let response: EpisodeResponse = try await api.get("/api/plex/dir/library/metadata/\(parentRatingKey)/children")
            let episodes = response.Metadata ?? []
            self.seasonEpisodes = episodes

            // Find next episode
            if let currentIndex = episodes.firstIndex(where: { $0.ratingKey == currentRatingKey }),
               currentIndex + 1 < episodes.count {
                self.nextEpisode = episodes[currentIndex + 1]
                print("📺 [Player] Next episode: \(self.nextEpisode?.title ?? "nil")")
            } else {
                self.nextEpisode = nil
                print("📺 [Player] No next episode")
            }
        } catch {
            print("⚠️ [Player] Failed to fetch next episode: \(error)")
            self.nextEpisode = nil
        }
    }

    private func updateCurrentMarker() {
        guard !markers.isEmpty else {
            if currentMarker != nil {
                print("⚠️ [Player] Clearing marker - no markers available")
                currentMarker = nil
            }
            return
        }

        let currentMs = Int(currentTime * 1000)

        // Debug: Log periodically what we're checking
        if Int(currentTime).isMultiple(of: 30) {
            print("🔍 [Player] Checking markers at \(currentMs)ms against \(markers.count) markers:")
            for marker in markers {
                print("   - \(marker.type): \(marker.startTimeOffset)-\(marker.endTimeOffset)ms")
            }
        }

        let newMarker = markers.first { marker in
            (marker.type == "intro" || marker.type == "credits") &&
            currentMs >= marker.startTimeOffset && currentMs <= marker.endTimeOffset
        }

        // Only update if changed to avoid unnecessary UI updates
        if newMarker?.id != currentMarker?.id {
            if let marker = newMarker {
                print("🎬 [Player] ✅ Marker ACTIVE: \(marker.type) at \(currentMs)ms (range: \(marker.startTimeOffset)-\(marker.endTimeOffset))")
            } else if currentMarker != nil {
                print("🎬 [Player] ❌ Marker ended at \(currentMs)ms")
            }
            currentMarker = newMarker
        }
    }

    private func updateNextEpisodeCountdown() {
        guard item.type == "episode", nextEpisode != nil, duration > 0 else {
            if nextEpisodeCountdown != nil {
                nextEpisodeCountdown = nil
            }
            return
        }

        // Start countdown at credits marker or last 30s
        let creditsMarker = markers.first { $0.type == "credits" }
        let triggerStart = creditsMarker != nil ? TimeInterval(creditsMarker!.startTimeOffset) / 1000.0 : max(0, duration - 30)

        if currentTime >= triggerStart {
            let remaining = max(0, Int(ceil(duration - currentTime)))
            if nextEpisodeCountdown != remaining {
                nextEpisodeCountdown = remaining
            }
        } else {
            if nextEpisodeCountdown != nil {
                nextEpisodeCountdown = nil
            }
        }
    }

    func skipMarker() {
        guard let marker = currentMarker else { return }
        let skipToTime = TimeInterval(marker.endTimeOffset) / 1000.0 + 1.0
        seek(to: skipToTime)
        print("⏭️ [Player] Skipped \(marker.type) to \(skipToTime)s")
    }

    private func loadStreamURL() async {
        isLoading = true
        error = nil

        do {
            // Validate this is a Plex item
            guard item.id.hasPrefix("plex:") else {
                throw NSError(
                    domain: "PlayerError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot play non-Plex content. Item must be in your Plex library.\n\nID: \(item.id)"]
                )
            }

            // Extract ratingKey from item.id
            let ratingKey = item.id.replacingOccurrences(of: "plex:", with: "")

            guard !ratingKey.isEmpty else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid item ID: \(item.id)"])
            }

            print("📺 [Player] Fetching stream URL for ratingKey: \(ratingKey)")
            print("📺 [Player] Item title: \(item.title) (type: \(item.type))")

            // Fetch markers (intro/credits)
            print("📺 [Player] About to call fetchMarkers...")
            await fetchMarkers(ratingKey: ratingKey)
            print("📺 [Player] fetchMarkers returned, markers count: \(markers.count)")

            // Fetch next episode if this is an episode - get parentRatingKey from metadata
            if item.type == "episode" {
                do {
                    struct EpMetadata: Decodable {
                        let parentRatingKey: String?
                    }
                    let meta: EpMetadata = try await api.get("/api/plex/metadata/\(ratingKey)")
                    if let parentKey = meta.parentRatingKey {
                        await fetchNextEpisode(parentRatingKey: parentKey, currentRatingKey: ratingKey)
                    }
                } catch {
                    print("⚠️ [Player] Failed to get parent rating key: \(error)")
                }
            }

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
                let container = (m?.container ?? "").lowercased()
                let vcodec = (m?.videoCodec ?? "").lowercased()
                let acodec = (m?.audioCodec ?? "").lowercased()

                // MPV can handle MKV/HEVC/TrueHD directly, AVPlayer cannot
                let allowDirect: Bool
                if playerBackend == .mpv {
                    // MPV: Allow all formats, it's very capable
                    allowDirect = true
                    print("✅ [Player] MPV backend: Allowing direct play for all codecs")
                } else {
                    // AVPlayer: Gate direct play for incompatible formats
                    let unsafeContainer = container.contains("mkv") || container.contains("mka")
                    let unsafeVideo = vcodec.contains("hevc") || vcodec.contains("dvh") || vcodec.contains("dvhe")
                    let unsafeAudio = acodec.contains("truehd") || acodec.contains("eac3")
                    allowDirect = !(unsafeContainer || unsafeVideo || unsafeAudio)
                    if !allowDirect {
                        print("🚫 [Player] AVPlayer: Skipping Direct Play due to incompatible container/codec: cont=\(container), v=\(vcodec), a=\(acodec)")
                    }
                }

                if allowDirect, let key = m?.Part?.first?.key, !key.isEmpty {
                    let direct = "\(baseUrl)\(key)?X-Plex-Token=\(token)"
                    directURL = URL(string: direct)
                    if directURL != nil { print("🎯 [Player] Attempting Direct Play: \(direct)") }
                }
            } catch {
                print("⚠️ [Player] Could not fetch metadata for direct play: \(error)")
            }

            var startURL: URL
            var isDirectPlay = false
            if let d = directURL {
                self.streamURL = d
                startURL = d
                isDirectPlay = true
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
            // Skip session handling for direct play
            if !isDirectPlay && startURL.absoluteString.contains("start.m3u8") {
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
                // MPV needs more time for transcoder to generate segments
                let delaySeconds = playerBackend == .mpv ? 5 : 1
                print("⏳ [Player] Waiting \(delaySeconds)s for transcoder to generate segments...")
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                print("✅ [Player] Proceeding with playback...")

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

            // Initialize player based on backend
            guard let finalURL = self.streamURL else {
                throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Stream URL not set"])
            }

            switch playerBackend {
            case .avplayer:
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

                // Auto-play immediately with current speed
                self.player?.rate = self.playbackSpeed
                self.isPlaying = true

                // Start progress tracking
                startProgressTracking()

            case .mpv:
                // Load file in MPV
                guard let mpvController = self.mpvController else {
                    throw NSError(domain: "PlayerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "MPV controller not initialized"])
                }

                print("🎬 [MPV] Loading file: \(finalURL.absoluteString)")
                mpvController.loadFile(finalURL.absoluteString)

                // MPV will handle playback automatically
                // Property and event callbacks will update our @Published properties

                // Start progress tracking
                startProgressTracking()
            }

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

                // Check for markers every 0.5s (matches web/mobile frequency)
                self.updateCurrentMarker()
                // Update next episode countdown
                self.updateNextEpisodeCountdown()
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
            self.player?.rate = self.playbackSpeed
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
        initialSeekApplied = true

        let ms = item.viewOffset ?? 0
        var seconds = TimeInterval(ms) / 1000.0
        if (seconds <= 2), let s = serverResumeSeconds { seconds = s }

        // If content is almost finished (within last 30s or >98% watched), restart from beginning
        if duration > 0 {
            let progress = seconds / duration
            let secondsRemaining = duration - seconds
            if progress > 0.98 || secondsRemaining < 30 {
                print("🔄 [Player] Content almost finished (progress: \(Int(progress * 100))%, \(Int(secondsRemaining))s remaining) - restarting from beginning")
                seconds = 0
            }
        }

        guard seconds > 2 else { // ignore trivial offsets
            return
        }

        seek(to: seconds)
        print("⏩ [Player] Resuming playback at \(Int(seconds))s")
    }

    // MARK: - Playback Controls

    func togglePlayPause() {
        switch playerBackend {
        case .avplayer:
            guard let player = player else { return }
            if isPlaying {
                player.pause()
                isPlaying = false
                stopProgressTracking()
            } else {
                player.rate = playbackSpeed // Restore playback speed
                isPlaying = true
                startProgressTracking()
            }
        case .mpv:
            guard let mpv = mpvController else { return }
            if isPlaying {
                mpv.pause()
                isPlaying = false
                stopProgressTracking()
            } else {
                mpv.play()
                isPlaying = true
                startProgressTracking()
            }
        }
    }

    func seek(to time: TimeInterval) {
        switch playerBackend {
        case .avplayer:
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
        case .mpv:
            guard let mpv = mpvController else { return }
            mpv.seek(to: time)
            print("✅ [MPV] Seeked to \(time)s")
            Task { @MainActor [weak self] in
                await self?.reportProgress()
            }
        }
    }

    func skip(seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    func setVolume(_ volume: Float) {
        self.volume = volume
        switch playerBackend {
        case .avplayer:
            player?.volume = isMuted ? 0 : volume
        case .mpv:
            mpvController?.setVolume(Double(volume * 100)) // MPV uses 0-100 scale
        }
    }

    func toggleMute() {
        isMuted.toggle()
        switch playerBackend {
        case .avplayer:
            player?.volume = isMuted ? 0 : volume
        case .mpv:
            mpvController?.setMute(isMuted)
        }
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        switch playerBackend {
        case .avplayer:
            player?.rate = isPlaying ? speed : 0
        case .mpv:
            mpvController?.setSpeed(Double(speed))
        }
        print("⚡ [Player] Playback speed set to \(speed)x")
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

    // MARK: - Stop Playback

    func stopPlayback() {
        print("🛑 [Player] Stopping playback")

        // Stop progress tracking immediately
        stopProgressTracking()

        // Stop based on backend
        switch playerBackend {
        case .avplayer:
            player?.pause()
        case .mpv:
            // Shutdown MPV completely to stop rendering
            mpvController?.shutdown()
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

            // Clean up based on backend
            switch self.playerBackend {
            case .avplayer:
                if let observer = self.timeObserver {
                    self.player?.removeTimeObserver(observer)
                    self.timeObserver = nil
                }
                self.player?.pause()
                self.player = nil
            case .mpv:
                // MPV shutdown already called in stopPlayback(), just release the controller
                // Shutdown is idempotent, so it's safe to call again if not already shut down
                if let controller = self.mpvController, !controller.isShutDown {
                    controller.shutdown()
                }
                self.mpvController = nil
            }

            self.stopProgressTracking()
            self.cancellables.removeAll()
        }
    }

    // MARK: - Next Episode

    func playNext() {
        guard let next = nextEpisode else { return }

        // Create MediaItem from next episode
        let nextItem = MediaItem(
            id: "plex:\(next.ratingKey)",
            title: next.title,
            type: "episode",
            thumb: next.thumb,
            art: nil,
            year: nil,
            rating: nil,
            duration: nil,
            viewOffset: nil,
            summary: next.summary,
            grandparentTitle: item.grandparentTitle,
            grandparentThumb: item.grandparentThumb,
            grandparentArt: item.grandparentArt,
            parentIndex: next.parentIndex,
            index: next.index
        )

        print("▶️ [Player] Play next: \(next.title)")

        // Stop current playback
        stopPlayback()

        // Call navigation callback
        onPlayNext?(nextItem)
    }

    func cancelCountdown() {
        nextEpisodeCountdown = nil
    }
}

// MARK: - Helper Response Types

struct EmptyResponse: Codable {}

struct PlayerMarker: Codable, Identifiable {
    let id: String
    let type: String // "intro", "credits", "commercial"
    let startTimeOffset: Int // milliseconds
    let endTimeOffset: Int // milliseconds

    enum CodingKeys: String, CodingKey {
        case id, type, startTimeOffset, endTimeOffset
    }
}

struct EpisodeMetadata: Codable, Identifiable, Equatable {
    let ratingKey: String
    let title: String
    let index: Int?
    let parentIndex: Int?
    let thumb: String?
    let summary: String?
    let viewOffset: Int? // Resume position in milliseconds
    let duration: Int? // Total duration in milliseconds
    let viewCount: Int? // Number of times watched

    var id: String { ratingKey }

    // Calculate progress percentage (0-100)
    var progressPercent: Int? {
        guard let dur = duration, dur > 0 else { return nil }

        // If fully watched (viewCount > 0), show 100%
        if let vc = viewCount, vc > 0 {
            if let o = viewOffset {
                let progress = Double(o) / Double(dur)
                // If within last 2% or viewOffset is very small, treat as fully watched
                if progress < 0.02 {
                    return 100
                }
                return Int(round(progress * 100))
            } else {
                // viewCount > 0 but no viewOffset = fully watched
                return 100
            }
        }

        // Partially watched - calculate from viewOffset
        guard let offset = viewOffset, offset > 0 else { return nil }
        let percent = Int((Double(offset) / Double(dur)) * 100)
        return min(100, max(0, percent))
    }

    static func == (lhs: EpisodeMetadata, rhs: EpisodeMetadata) -> Bool {
        lhs.ratingKey == rhs.ratingKey
    }
}
