//
//  MPVVideoView.swift
//  FlixorMac
//
//  MPV video rendering view using CAOpenGLLayer
//

import SwiftUI
import AppKit

struct MPVVideoView: NSViewRepresentable {
    let mpvController: MPVPlayerController

    func makeNSView(context: Context) -> MPVNSView {
        let view = MPVNSView()
        view.setupMPVRendering(controller: mpvController)
        return view
    }

    func updateNSView(_ nsView: MPVNSView, context: Context) {
        // No updates needed
    }

    static func dismantleNSView(_ nsView: MPVNSView, coordinator: ()) {
        // Stop rendering BEFORE the view is deallocated
        nsView.stopRendering()
    }
}

class MPVNSView: NSView {
    private var displayLink: CVDisplayLink?
    private var videoLayer: MPVVideoLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        // Create and setup the video layer
        let layer = MPVVideoLayer()
        self.layer = layer
        self.videoLayer = layer
        self.wantsLayer = true

        // Configure the view
        autoresizingMask = [.width, .height]
        wantsBestResolutionOpenGLSurface = true

        print("✅ [MPVView] Layer setup complete")
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        guard let videoLayer = videoLayer else {
            print("❌ [MPVView] Cannot setup MPV rendering: layer not initialized")
            return
        }

        videoLayer.setupMPVRendering(controller: controller)
    }

    func stopRendering() {
        print("🛑 [MPVView] Stopping rendering")
        stopDisplayLink()
        videoLayer?.mpvController = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            startDisplayLink()
        } else {
            stopDisplayLink()
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }

        let displayLinkCallback: CVDisplayLinkOutputCallback = { _, _, _, _, _, context in
            guard let context = context else { return kCVReturnSuccess }
            let view = Unmanaged<MPVNSView>.fromOpaque(context).takeUnretainedValue()

            DispatchQueue.main.async {
                view.videoLayer?.setNeedsDisplay()
            }

            return kCVReturnSuccess
        }

        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)

        if let link = link {
            CVDisplayLinkSetOutputCallback(link, displayLinkCallback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(link)
            self.displayLink = link
            print("✅ [MPVView] Display link started")
        }
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            self.displayLink = nil
            print("🛑 [MPVView] Display link stopped")
        }
    }

    deinit {
        stopDisplayLink()
        print("🧹 [MPVView] Cleaned up")
    }
}
