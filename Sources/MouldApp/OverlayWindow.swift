import AppKit
import MetalKit
import MouldCore
import MouldRender

/// A borderless, click-through, transparent window covering one screen, floating above
/// everything except the screensaver and the lock screen.
@MainActor
final class OverlayWindow: NSWindow {
    let displayID: CGDirectDisplayID
    let mouldView: MouldView

    init(screen: NSScreen, renderer: MouldRenderer) {
        displayID = screen.displayID
        mouldView = MouldView(frame: NSRect(origin: .zero, size: screen.frame.size), renderer: renderer)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // One below the screensaver: over menus, the Dock and full-screen apps, but never over the saver.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
        contentView = mouldView
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Metal view that asks its provider for a frame whenever it is told to redraw.
@MainActor
final class MouldView: MTKView, MTKViewDelegate {
    private let renderer: MouldRenderer
    var frameProvider: (() -> MouldFrame?)?

    init(frame: NSRect, renderer: MouldRenderer) {
        self.renderer = renderer
        super.init(frame: frame, device: renderer.device)
        colorPixelFormat = MouldRenderer.pixelFormat
        framebufferOnly = true
        layer?.isOpaque = false
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        // We drive redraws ourselves: mould changes slowly, so there is no need for 60 fps.
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = true
        delegate = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let frame = frameProvider?(),
              let pass = currentRenderPassDescriptor,
              let drawable = currentDrawable,
              let commandBuffer = renderer.commandQueue.makeCommandBuffer() else { return }
        renderer.encode(frame, commandBuffer: commandBuffer, pass: pass)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
