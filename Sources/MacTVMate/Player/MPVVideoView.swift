import AppKit
import CMPV
import OpenGL.GL3
import SwiftUI

/// CAOpenGLLayer that asks libmpv to draw into the layer's framebuffer.
final class MPVLayer: CAOpenGLLayer {
    private weak var controller: MPVController?
    private let renderQueue = DispatchQueue(label: "mpv.render", qos: .userInteractive)

    init(controller: MPVController) {
        self.controller = controller
        super.init()
        isAsynchronous = false
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        backgroundColor = NSColor.black.cgColor
    }

    override init(layer: Any) {
        let other = layer as! MPVLayer
        controller = other.controller
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attrs: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            kCGLPFAAllowOfflineRenderers,
            kCGLPFAColorSize, CGLPixelFormatAttribute(32),
            CGLPixelFormatAttribute(0),
        ]
        var pix: CGLPixelFormatObj?
        var count: GLint = 0
        CGLChoosePixelFormat(attrs, &pix, &count)
        return pix!
    }

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        var ctx: CGLContextObj?
        CGLCreateContext(pf, nil, &ctx)
        var swap: GLint = 1
        CGLSetParameter(ctx!, kCGLCPSwapInterval, &swap)
        CGLEnable(ctx!, kCGLCEMPEngine)
        CGLSetCurrentContext(ctx)
        controller?.createRenderContext()
        controller?.requestRedraw = { [weak self] in self?.renderQueue.async { self?.display() } }
        controller?.setRenderUpdateCallback({ ctx in
            let layer = Unmanaged<MPVLayer>.fromOpaque(ctx!).takeUnretainedValue()
            layer.renderQueue.async { layer.display() }
        }, context: Unmanaged.passUnretained(self).toOpaque())
        return ctx!
    }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        true
    }

    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj, forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let controller else { return }
        _ = controller.renderUpdate()
        var fbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &fbo)
        var viewport: [GLint] = [0, 0, 0, 0]
        glGetIntegerv(GLenum(GL_VIEWPORT), &viewport)
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        // While switching channels, keep the screen black rather than the previous channel's last frame.
        if !controller.blankVideo { controller.render(fbo: fbo, width: viewport[2], height: viewport[3]) }
        glFlush()
        controller.reportSwap()
    }

    override func display() {
        super.display()
        CATransaction.flush()
    }
}

final class MPVNSView: NSView {
    let mpvLayer: MPVLayer

    init(controller: MPVController) {
        mpvLayer = MPVLayer(controller: controller)
        super.init(frame: .zero)
        wantsLayer = true
        layer = mpvLayer
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        mpvLayer.contentsScale = window?.backingScaleFactor ?? 2
        mpvLayer.setNeedsDisplay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        mpvLayer.contentsScale = window?.backingScaleFactor ?? 2
        mpvLayer.setNeedsDisplay()
        mpvLayer.display()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        mpvLayer.setNeedsDisplay()
    }
}

struct MPVVideoView: NSViewRepresentable {
    let controller: MPVController

    func makeNSView(context: Context) -> MPVNSView { MPVNSView(controller: controller) }
    func updateNSView(_ nsView: MPVNSView, context: Context) {}
}
