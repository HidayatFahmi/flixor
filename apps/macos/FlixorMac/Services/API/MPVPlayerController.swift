//
//  MPVPlayerController.swift
//  FlixorMac
//
//  MPV player controller for video playback
//

import Foundation
import AppKit

class MPVPlayerController {
    // MARK: - Properties

    /// The mpv handle
    private var mpv: OpaquePointer!

    /// Render context for video output
    private var mpvRenderContext: OpaquePointer?

    /// OpenGL context
    private var openGLContext: CGLContextObj?

    /// Dispatch queue for mpv events
    private lazy var queue = DispatchQueue(label: "com.flixor.mpv.controller", qos: .userInitiated)

    /// Shutdown flag to prevent double-shutdown
    private var isShuttingDown = false
    private let shutdownLock = NSLock()

    /// Public property to check if shut down
    var isShutDown: Bool {
        return isShuttingDown
    }

    /// Callback for when mpv requests a video redraw
    var videoUpdateCallback: (() -> Void)?

    /// Callback for property changes
    var onPropertyChange: ((String, Any?) -> Void)?

    /// Callback for events
    var onEvent: ((String) -> Void)?

    /// Callback for HDR detection
    var onHDRDetected: ((Bool, String?, String?) -> Void)?

    // MARK: - Initialization

    init() {
        setupMPV()
    }

    deinit {
        // Only shutdown if not already done
        if !isShuttingDown && mpv != nil {
            print("⚠️ [MPV] Cleanup in deinit (should have been called explicitly)")
            shutdown()
        }
    }

    // MARK: - Setup

    private func setupMPV() {
        // Create mpv instance
        mpv = mpv_create()
        guard mpv != nil else {
            print("❌ [MPV] Failed to create mpv instance")
            return
        }

        // Configure mpv options
        configureOptions()

        // Set log level
        mpv_request_log_messages(mpv, "warn")

        // Set wakeup callback for events
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx = ctx else { return }
            let controller = Unmanaged<MPVPlayerController>.fromOpaque(ctx).takeUnretainedValue()
            controller.readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())

        // Observe important properties
        observeProperties()

        // Initialize mpv
        let status = mpv_initialize(mpv)
        if status < 0 {
            print("❌ [MPV] Failed to initialize: \(String(cString: mpv_error_string(status)))")
            return
        }

        print("✅ [MPV] Initialized successfully")
    }

    private func configureOptions() {
        // Video output - use libmpv for rendering
        setOption("vo", value: "libmpv")

        // Force OpenGL GPU API (align with IINA). This avoids odd render paths.
        setOption("gpu-api", value: "opengl")

        // Keep aspect ratio
        setOption("keepaspect", value: "yes")

        // Hardware decoding
        setOption("hwdec", value: "auto")

        // OpenGL interop
        setOption("gpu-hwdec-interop", value: "auto")

        // Disable on-screen display
        setOption("osd-level", value: "0")

        // Cache settings for streaming - increased for HLS
        setOption("cache", value: "yes")
        setOption("demuxer-max-bytes", value: "400MiB")
        setOption("demuxer-max-back-bytes", value: "150MiB")
        setOption("demuxer-readahead-secs", value: "20")

        // Network settings for HLS streaming
        setOption("user-agent", value: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15")
        setOption("http-header-fields", value: "Accept: */*")
        setOption("tls-verify", value: "no")
        setOption("stream-lavf-o", value: "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5")

        // HLS specific options
        setOption("hls-bitrate", value: "max")

        // Audio settings
        setOption("audio-channels", value: "stereo")
        setOption("volume-max", value: "100")

        // macOS GPU acceleration
        setOption("macos-force-dedicated-gpu", value: "yes")

        // Debug logging (only in Debug builds)
        #if DEBUG
        setOption("msg-level", value: "all=v")
        setOption("log-file", value: "/tmp/mpv-flixor.log")
        #endif

        // Note: HDR options (target-trc, target-prim, target-peak, tone-mapping)
        // will be set dynamically when HDR content is detected (IINA approach)

        print("✅ [MPV] Options configured")
    }

    private func observeProperties() {
        // Observe playback state
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "volume", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 0, "mute", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "seeking", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 0, "paused-for-cache", MPV_FORMAT_FLAG)

        // Observe video properties for HDR detection (IINA approach)
        mpv_observe_property(mpv, 0, "video-params/primaries", MPV_FORMAT_STRING)
        mpv_observe_property(mpv, 0, "video-params/gamma", MPV_FORMAT_STRING)
    }

    // MARK: - Rendering Setup

    func initializeRendering(openGLContext: CGLContextObj) {
        guard mpv != nil else {
            print("❌ [MPV] Cannot initialize rendering: mpv not initialized")
            return
        }

        self.openGLContext = openGLContext

        // Setup OpenGL init params
        var openGLInitParams = mpv_opengl_init_params(
            get_proc_address: { ctx, name in
                guard let name = name else { return nil }
                let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII)
                let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString)
                return CFBundleGetFunctionPointerForName(bundle, symbolName)
            },
            get_proc_address_ctx: nil
        )

        // Setup render params
        let apiType = UnsafeMutableRawPointer(mutating: (MPV_RENDER_API_TYPE_OPENGL as NSString).utf8String)
        var advanced: CInt = 1

        withUnsafeMutablePointer(to: &openGLInitParams) { glInitParams in
            withUnsafeMutablePointer(to: &advanced) { advancedPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: glInitParams),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: advancedPtr),
                    mpv_render_param()
                ]

                let status = mpv_render_context_create(&mpvRenderContext, mpv, &params)
                if status < 0 {
                    print("❌ [MPV] Failed to create render context: \(String(cString: mpv_error_string(status)))")
                    return
                }

                // Set update callback
                mpv_render_context_set_update_callback(mpvRenderContext, { ctx in
                    guard let ctx = ctx else { return }
                    let controller = Unmanaged<MPVPlayerController>.fromOpaque(ctx).takeUnretainedValue()
                    controller.videoUpdateCallback?()
                }, Unmanaged.passUnretained(self).toOpaque())

                print("✅ [MPV] Rendering initialized")
            }
        }
    }

    // MARK: - Playback Control

    func loadFile(_ url: String) {
        guard mpv != nil else {
            print("❌ [MPV] Cannot load file: mpv not initialized")
            return
        }

        print("📺 [MPV] Loading file: \(url)")
        // Use mpv_command_string for simpler command execution
        let commandString = "loadfile \"\(url)\" replace"
        let status = mpv_command_string(mpv, commandString)
        if status < 0 {
            print("❌ [MPV] Failed to load file: \(String(cString: mpv_error_string(status)))")
        }
    }

    func play() {
        setProperty("pause", value: false)
    }

    func pause() {
        setProperty("pause", value: true)
    }

    func togglePlayPause() {
        command(.cyclePause)
    }

    func seek(to seconds: Double) {
        setProperty("time-pos", value: seconds)
    }

    func seekRelative(seconds: Double) {
        command(.seek, args: ["\(seconds)", "relative"])
    }

    func setVolume(_ volume: Double) {
        setProperty("volume", value: volume)
    }

    func setMute(_ muted: Bool) {
        setProperty("mute", value: muted)
    }

    func setSpeed(_ speed: Double) {
        setProperty("speed", value: speed)
    }

    func stop() {
        command(.stop)
    }

    // MARK: - Rendering

    func render(width: Int, height: Int, fbo: GLint) {
        guard let renderContext = mpvRenderContext else { return }

        // Setup render parameters
        var fboValue = fbo
        var width = Int32(width)
        var height = Int32(height)

        withUnsafeMutablePointer(to: &fboValue) { fboPtr in
            withUnsafeMutablePointer(to: &width) { widthPtr in
                withUnsafeMutablePointer(to: &height) { heightPtr in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: nil),
                        mpv_render_param()
                    ]

                    mpv_render_context_render(renderContext, &params)
                }
            }
        }
    }

    func reportSwap() {
        guard let renderContext = mpvRenderContext else { return }
        mpv_render_context_report_swap(renderContext)
    }

    func shouldRenderUpdateFrame() -> Bool {
        guard !isShuttingDown, let renderContext = mpvRenderContext else { return false }
        let flags = mpv_render_context_update(renderContext)
        return (flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue)) != 0
    }

    func getRenderContext() -> OpaquePointer? {
        guard !isShuttingDown else { return nil }
        return mpvRenderContext
    }

    // Provide ICC profile to mpv render context (like IINA's MPV_RENDER_PARAM_ICC_PROFILE path).
    func setRenderICCProfile(_ colorSpace: NSColorSpace) {
        guard let renderContext = mpvRenderContext else { return }
        guard var iccData = colorSpace.iccProfileData else {
            let name = colorSpace.localizedName ?? "unnamed"
            print("⚠️ [MPV] Color space \(name) has no ICC data")
            return
        }
        iccData.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress, ptr.count > 0 else { return }
            var byteArray = mpv_byte_array(data: base.assumingMemoryBound(to: UInt8.self), size: ptr.count)
            withUnsafeMutableBytes(of: &byteArray) { bptr in
                let param = mpv_render_param(type: MPV_RENDER_PARAM_ICC_PROFILE, data: bptr.baseAddress)
                mpv_render_context_set_parameter(renderContext, param)
            }
        }
    }

    // MARK: - Property Management

    func getProperty<T>(_ name: String, type: PropertyType) -> T? {
        guard mpv != nil else { return nil }

        switch type {
        case .flag:
            var value: Int64 = 0
            mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value)
            return (value != 0) as? T

        case .int64:
            var value: Int64 = 0
            mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value)
            return value as? T

        case .double:
            var value: Double = 0
            mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value)
            return value as? T

        case .string:
            let cstr = mpv_get_property_string(mpv, name)
            let str = cstr == nil ? nil : String(cString: cstr!)
            mpv_free(cstr)
            return str as? T
        }
    }

    private func setProperty(_ name: String, value: Any) {
        guard mpv != nil else { return }

        if let boolValue = value as? Bool {
            var data: Int = boolValue ? 1 : 0
            mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
        } else if let intValue = value as? Int64 {
            var data = intValue
            mpv_set_property(mpv, name, MPV_FORMAT_INT64, &data)
        } else if let doubleValue = value as? Double {
            var data = doubleValue
            mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data)
        } else if let stringValue = value as? String {
            mpv_set_property_string(mpv, name, stringValue)
        }
    }

    /// Set HDR properties dynamically (IINA approach)
    func setHDRProperties(primaries: String) {
        guard mpv != nil else { return }

        // Disable ICC profile for HDR
        setProperty("icc-profile-auto", value: false)

        // Set target color space to PQ (HDR)
        // PQ videos will be displayed as-is, HLG videos will be converted to PQ
        setProperty("target-trc", value: "pq")
        setProperty("target-prim", value: primaries)

        // CRITICAL: IINA's default is enableToneMapping=false
        // This lets the display handle HDR natively via macOS EDR
        // Disable tone mapping for native HDR display (IINA default)
        setProperty("target-peak", value: "auto")
        setProperty("tone-mapping", value: "")

        // Tag screenshots with colorspace
        setProperty("screenshot-tag-colorspace", value: true)

        print("✅ [MPV] HDR properties set: target-trc=pq, target-prim=\(primaries), target-peak=auto, tone-mapping=disabled (native EDR)")
    }

    /// Set SDR properties dynamically (IINA approach)
    func setSDRProperties() {
        guard mpv != nil else { return }
        // Enable ICC auto so mpv uses the provided ICC profile via render param
        setOption("icc-profile-auto", value: "yes")
        setProperty("target-trc", value: "auto")
        setProperty("target-prim", value: "auto")
        setProperty("target-peak", value: "auto")
        setProperty("tone-mapping", value: "auto")
        setProperty("screenshot-tag-colorspace", value: false)

        print("✅ [MPV] SDR properties set")
    }

    private func setOption(_ name: String, value: String) {
        guard mpv != nil else { return }
        let status = mpv_set_option_string(mpv, name, value)
        if status < 0 {
            print("⚠️ [MPV] Failed to set option \(name)=\(value): \(String(cString: mpv_error_string(status)))")
        }
    }

    // MARK: - Color Management

    /// Set ICC profile path for the current renderer and disable auto detection, like IINA.
    /// Pass empty string to clear.
    func setICCProfile(path: String?) {
        guard mpv != nil else { return }
        let profilePath = path ?? ""
        _ = mpv_set_option_string(mpv, "icc-profile", profilePath)
        _ = mpv_set_option_string(mpv, "icc-profile-auto", "no")
        if profilePath.isEmpty {
            print("🎨 [MPV] ICC profile cleared; auto=no")
        } else {
            print("🎨 [MPV] ICC profile set: \(profilePath); auto=no")
        }
    }

    // MARK: - Commands

    private func command(_ cmd: MPVCommand, args: [String] = []) {
        guard mpv != nil else { return }

        var strArgs = args
        strArgs.insert(cmd.rawValue, at: 0)
        strArgs.append("")

        let cArgs = strArgs.map { $0.withCString { strdup($0) } }
        defer {
            cArgs.forEach { free(UnsafeMutablePointer(mutating: $0)) }
        }

        var mutableArgs = cArgs.map { UnsafePointer($0) }
        mpv_command(mpv, &mutableArgs)
    }

    // MARK: - Event Handling

    private func readEvents() {
        queue.async { [weak self] in
            guard let self = self, self.mpv != nil else { return }

            while true {
                let event = mpv_wait_event(self.mpv, 0)
                guard let event = event else { break }

                let eventId = event.pointee.event_id
                if eventId == MPV_EVENT_NONE {
                    break
                }

                self.handleEvent(event)

                if eventId == MPV_EVENT_SHUTDOWN {
                    break
                }
            }
        }
    }

    private func handleEvent(_ event: UnsafePointer<mpv_event>) {
        let eventId = event.pointee.event_id
        let eventName = String(cString: mpv_event_name(eventId))

        switch eventId {
        case MPV_EVENT_PROPERTY_CHANGE:
            let data = event.pointee.data.assumingMemoryBound(to: mpv_event_property.self)
            let property = data.pointee
            let propertyName = String(cString: property.name)

            let value: Any? = {
                switch property.format {
                case MPV_FORMAT_FLAG:
                    return property.data.load(as: Bool.self)
                case MPV_FORMAT_INT64:
                    return property.data.load(as: Int64.self)
                case MPV_FORMAT_DOUBLE:
                    return property.data.load(as: Double.self)
                case MPV_FORMAT_STRING:
                    let str = property.data.load(as: UnsafePointer<CChar>.self)
                    return String(cString: str)
                default:
                    return nil
                }
            }()

            // Check for HDR detection (IINA approach)
            if propertyName == "video-params/primaries" || propertyName == "video-params/gamma" {
                self.detectHDR()
            }

            DispatchQueue.main.async { [weak self] in
                self?.onPropertyChange?(propertyName, value)
            }

        case MPV_EVENT_START_FILE:
            print("📺 [MPV] File started")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-started")
            }

        case MPV_EVENT_FILE_LOADED:
            print("✅ [MPV] File loaded")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-loaded")
            }

        case MPV_EVENT_END_FILE:
            print("🏁 [MPV] File ended")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("file-ended")
            }

        case MPV_EVENT_PLAYBACK_RESTART:
            print("▶️ [MPV] Playback restarted")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("playback-restart")
            }

        case MPV_EVENT_SEEK:
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("seek")
            }

        case MPV_EVENT_SHUTDOWN:
            print("🛑 [MPV] Shutdown")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?("shutdown")
            }

        case MPV_EVENT_LOG_MESSAGE:
            let logData = event.pointee.data.assumingMemoryBound(to: mpv_event_log_message.self)
            let log = logData.pointee
            let prefix = String(cString: log.prefix)
            let level = String(cString: log.level)
            let text = String(cString: log.text).trimmingCharacters(in: .whitespacesAndNewlines)
            print("📝 [MPV] [\(prefix)] \(level): \(text)")

        default:
            break
        }
    }

    // MARK: - HDR Detection

    private func detectHDR() {
        // Get video properties (IINA approach)
        guard let gamma: String = getProperty("video-params/gamma", type: .string),
              let primaries: String = getProperty("video-params/primaries", type: .string) else {
            return
        }

        // HDR videos use PQ (Perceptual Quantizer) or HLG (Hybrid Log-Gamma) transfer functions
        let isHDR = gamma == "pq" || gamma == "hlg"

        if isHDR {
            print("🌈 [MPV] HDR detected! Gamma: \(gamma), Primaries: \(primaries)")
        }

        // Notify via callback
        DispatchQueue.main.async { [weak self] in
            self?.onHDRDetected?(isHDR, gamma, primaries)
        }
    }

    // MARK: - Shutdown

    func shutdown() {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }

        // Prevent double shutdown
        guard !isShuttingDown else {
            print("⚠️ [MPV] Already shutting down, skipping")
            return
        }

        guard mpv != nil else {
            print("⚠️ [MPV] Already shut down")
            return
        }

        isShuttingDown = true
        print("🛑 [MPV] Shutting down")

        // Clear callbacks first to stop any new render requests
        videoUpdateCallback = nil
        onPropertyChange = nil
        onEvent = nil

        // CRITICAL: Free render context BEFORE terminating mpv
        // This must be done or mpv_terminate_destroy will abort
        if let renderContext = mpvRenderContext {
            print("🛑 [MPV] Freeing render context...")
            mpv_render_context_set_update_callback(renderContext, nil, nil)

            // Lock GL context if available
            if let glContext = openGLContext {
                CGLLockContext(glContext)
                CGLSetCurrentContext(glContext)
            }

            mpv_render_context_free(renderContext)
            mpvRenderContext = nil

            if let glContext = openGLContext {
                CGLSetCurrentContext(nil)
                CGLUnlockContext(glContext)
            }

            print("✅ [MPV] Render context freed")
        }

        // Clear wakeup callback before draining events
        if let mpv = mpv {
            mpv_set_wakeup_callback(mpv, nil, nil)
        }

        // Drain all pending events before terminating
        if let mpv = mpv {
            print("🔄 [MPV] Draining event queue...")
            while true {
                let event = mpv_wait_event(mpv, 0)
                guard let event = event, event.pointee.event_id != MPV_EVENT_NONE else {
                    break
                }
            }
            print("✅ [MPV] Event queue drained")
        }

        // Small delay to ensure everything is settled
        Thread.sleep(forTimeInterval: 0.05)

        // Terminate MPV
        if let mpv = mpv {
            print("🛑 [MPV] Calling mpv_terminate_destroy...")
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }

        openGLContext = nil
        print("✅ [MPV] Shutdown complete")
    }
}

// MARK: - Supporting Types

enum MPVCommand: String {
    case loadfile = "loadfile"
    case stop = "stop"
    case seek = "seek"
    case cyclePause = "cycle"
    case quit = "quit"
}

enum PropertyType {
    case flag
    case int64
    case double
    case string
}
