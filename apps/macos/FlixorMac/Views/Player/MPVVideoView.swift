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
    var videoLayer: MPVVideoLayer? // Internal access for PiP controls
    var isPiPTransitioning = false // Flag to prevent display link stops during PiP

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

        // CRITICAL: Enable EDR on the NSView (IINA approach)
        if #available(macOS 10.15, *) {
            wantsExtendedDynamicRangeOpenGLSurface = true
        }
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        guard let videoLayer = videoLayer else { return }
        videoLayer.setupMPVRendering(controller: controller)
    }

    func stopRendering() {
        stopDisplayLink()
        videoLayer?.mpvController = nil
    }

    override func layout() {
        super.layout()
        // Always update layer size on layout to handle PiP transitions
        updateLayerSize()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        // Also update when view is resized
        updateLayerSize()
    }

    // Force update layer size to match view bounds
    func updateLayerSize() {
        guard let videoLayer = videoLayer else { return }

        let newBounds = CGRect(origin: .zero, size: bounds.size)
        if videoLayer.bounds != newBounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true) // Disable implicit animations
            videoLayer.bounds = newBounds
            videoLayer.frame = newBounds
            CATransaction.commit()
        }

        // Keep contentsScale aligned with current backing scale factor
        if let scale = window?.backingScaleFactor {
            videoLayer.contentsScale = scale
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Update display link for new window (IINA pattern)
            // This ensures the display link targets the correct screen
            if displayLink != nil {
                // Display link already exists, force a redraw in the new window
                videoLayer?.setNeedsDisplay()
                needsLayout = true
                layout()
            } else {
                startDisplayLink()
            }
            updateLayerSize()
        } else {
            // Don't stop display link during PiP transitions
            if !isPiPTransitioning {
                stopDisplayLink()
            }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerSize()
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
        }
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            self.displayLink = nil
        }
    }

    deinit {
        stopDisplayLink()
    }
}
