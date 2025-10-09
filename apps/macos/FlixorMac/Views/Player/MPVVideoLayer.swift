//
//  MPVVideoLayer.swift
//  FlixorMac
//
//  CAOpenGLLayer for MPV video rendering
//

import Cocoa
import OpenGL.GL
import OpenGL.GL3

class MPVVideoLayer: CAOpenGLLayer {
    weak var mpvController: MPVPlayerController?

    private let cglContext: CGLContextObj
    private let cglPixelFormat: CGLPixelFormatObj

    override init() {
        // Create pixel format
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAColorSize, CGLPixelFormatAttribute(32),
            kCGLPFADepthSize, CGLPixelFormatAttribute(24),
            CGLPixelFormatAttribute(0)
        ]

        var pix: CGLPixelFormatObj?
        var npix: GLint = 0
        CGLChoosePixelFormat(attrs, &pix, &npix)

        guard let pixelFormat = pix else {
            fatalError("❌ [MPVLayer] Failed to create pixel format")
        }

        self.cglPixelFormat = pixelFormat

        // Create OpenGL context
        var ctx: CGLContextObj?
        CGLCreateContext(pixelFormat, nil, &ctx)

        guard let context = ctx else {
            fatalError("❌ [MPVLayer] Failed to create OpenGL context")
        }

        // Enable vsync
        var swapInterval: GLint = 1
        CGLSetParameter(context, kCGLCPSwapInterval, &swapInterval)

        self.cglContext = context

        super.init()

        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
        isAsynchronous = false
        isOpaque = true

        print("✅ [MPVLayer] Initialized")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(layer: Any) {
        let previousLayer = layer as! MPVVideoLayer
        mpvController = previousLayer.mpvController
        cglPixelFormat = previousLayer.cglPixelFormat
        cglContext = previousLayer.cglContext
        super.init(layer: layer)
    }

    func setupMPVRendering(controller: MPVPlayerController) {
        self.mpvController = controller

        // Initialize MPV rendering with our CGL context
        CGLLockContext(cglContext)
        CGLSetCurrentContext(cglContext)

        controller.initializeRendering(openGLContext: cglContext)

        // Set update callback
        controller.videoUpdateCallback = { [weak self] in
            DispatchQueue.main.async {
                self?.setNeedsDisplay()
            }
        }

        CGLUnlockContext(cglContext)

        print("✅ [MPVLayer] MPV rendering setup complete")
    }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                         forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        guard let mpvController = mpvController else { return false }
        return mpvController.shouldRenderUpdateFrame()
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
                      forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let mpvController = mpvController,
              let renderContext = mpvController.getRenderContext() else {
            glClearColor(0, 0, 0, 1)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        // Get framebuffer info
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fbo)

        var dims: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &dims)

        // Create FBO structure
        var data = mpv_opengl_fbo(
            fbo: Int32(fbo != 0 ? fbo : 1),
            w: Int32(dims[2]),
            h: Int32(dims[3]),
            internal_format: 0
        )

        var flip: CInt = 1

        withUnsafeMutablePointer(to: &data) { dataPtr in
            withUnsafeMutablePointer(to: &flip) { flipPtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: .init(dataPtr)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: .init(flipPtr)),
                    mpv_render_param()
                ]

                mpv_render_context_render(renderContext, &params)
            }
        }

        glFlush()
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        return cglPixelFormat
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        return cglContext
    }
}
