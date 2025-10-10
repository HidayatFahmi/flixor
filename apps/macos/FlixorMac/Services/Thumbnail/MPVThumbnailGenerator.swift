//
//  MPVThumbnailGenerator.swift
//  FlixorMac
//
//  Coordinates thumbnail generation using self-contained MPV instance
//

import Foundation
import AppKit
import Combine

/// Manages thumbnail generation for MPV player
class MPVThumbnailGenerator: ObservableObject {
    // MARK: - Properties

    private weak var mpvController: MPVPlayerController?
    private let cache = ThumbnailCache()
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.05 // 50ms
    private let thumbnailPlayer = ThumbnailMPVPlayer()
    private var currentVideoURL: String?

    /// Observable property indicating if thumbnails are available
    @Published var isAvailable: Bool = false

    // MARK: - Initialization

    init(mpvController: MPVPlayerController) {
        self.mpvController = mpvController
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // No-op: PlayerViewModel will call onVideoLoaded() directly
    }

    /// Called by PlayerViewModel when a video file is loaded
    func onVideoLoaded(url: String) {
        print("📸 [ThumbnailGenerator] Video loaded: \(url)")
        currentVideoURL = url

        // Load the same video in thumbnail player
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.thumbnailPlayer.loadVideo(url: url)
            DispatchQueue.main.async {
                self?.isAvailable = true
                print("✅ [ThumbnailGenerator] Ready for thumbnail generation")
            }
        }
    }

    // MARK: - Public Methods

    /// Generate a thumbnail at a specific timestamp
    /// - Parameters:
    ///   - time: Time in seconds
    ///   - completion: Called with the generated image or nil on failure
    func generateThumbnail(at time: Double, completion: @escaping (NSImage?) -> Void) {
        // Check cache first (instant)
        if let cached = cache.get(at: time) {
            print("⚡️ [ThumbnailGenerator] Cache hit for \(time)s")
            completion(cached)
            return
        }

        // Debounce requests to avoid overwhelming the system
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            self?.requestThumbnail(at: time, completion: completion)
        }
    }

    /// Pre-fetch thumbnails around a specific time
    /// - Parameter centerTime: Center timestamp in seconds
    /// - Parameter range: Time range in seconds (default: 5 seconds)
    func prefetchThumbnails(around centerTime: Double, range: Double = 5.0) {
        // Pre-fetch thumbnails at 1-second intervals
        let startTime = max(0, centerTime - range)
        let endTime = centerTime + range
        var currentTime = startTime

        while currentTime <= endTime {
            // Skip if already cached
            if cache.get(at: currentTime) == nil {
                requestThumbnail(at: currentTime) { _ in
                    // Silent completion
                }
            }
            currentTime += 1.0
        }

        print("🔮 [ThumbnailGenerator] Prefetching thumbnails from \(startTime)s to \(endTime)s")
    }

    /// Clear all cached thumbnails
    func clearCache() {
        cache.clearAll()
    }

    // MARK: - Private Methods

    private func requestThumbnail(at time: Double, completion: @escaping (NSImage?) -> Void) {
        guard isAvailable, currentVideoURL != nil else {
            print("⚠️ [ThumbnailGenerator] Thumbnails not available yet")
            DispatchQueue.main.async {
                completion(nil)
            }
            return
        }

        print("📸 [ThumbnailGenerator] Requesting thumbnail at \(time)s")

        // Generate thumbnail on background thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // Use our self-contained thumbnail player
            guard let image = self.thumbnailPlayer.generateThumbnail(at: time) else {
                print("❌ [ThumbnailGenerator] Failed to generate thumbnail at \(time)s")
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            // Cache the thumbnail
            self.cache.set(image: image, at: time)

            // Return on main thread
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}
