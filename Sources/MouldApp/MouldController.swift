import AppKit
import MouldCore
import MouldRender
import QuartzCore

/// Owns the growth clock, one overlay per screen, and the redraw loop.
@MainActor
final class MouldController {
    static let duration: TimeInterval = 60 * 60

    let renderer: MouldRenderer
    private(set) var clock: GrowthClock
    private var seed: UInt64 = .random(in: 1...UInt64.max)
    private var overlays: [OverlayWindow] = []
    private var simulations: [CGDirectDisplayID: MouldSimulation] = [:]
    private var wipe: WipeAnimation?
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTick = CACurrentMediaTime()
    private var lastDrawnElapsed: TimeInterval = -1
    private var activity: NSObjectProtocol?
    private var captureTimer: Timer?
    private var screenshotGuard = ScreenshotGuard(windowPicker: windowPickerCursor())
    private var steppedAside = false

    var onStateChange: (() -> Void)?

    var theme: Theme {
        didSet { Settings.theme = theme; replant(); redraw() }
    }
    var opacity: Double {
        didSet { Settings.opacity = opacity; redraw() }
    }
    var pausesWhenAway: Bool {
        didSet { Settings.pausesWhenAway = pausesWhenAway; applyClockSettings() }
    }
    var speed: Double {
        didSet { applyClockSettings(); scheduleTimer() }
    }
    /// Step aside (turn transparent) while macOS's screenshot tools are open.
    var hidesDuringScreenshots: Bool {
        didSet { Settings.hidesDuringScreenshots = hidesDuringScreenshots; updateVisibility() }
    }

    init(renderer: MouldRenderer, options: LaunchOptions) {
        self.renderer = renderer
        theme = options.theme ?? Settings.theme
        opacity = Settings.opacity
        pausesWhenAway = Settings.pausesWhenAway
        hidesDuringScreenshots = Settings.hidesDuringScreenshots
        speed = options.speed
        clock = GrowthClock(speed: options.speed)
        clock.jump(to: options.startMinutes * 60)
        applyClockSettings()
    }

    // MARK: - Lifecycle

    func start() {
        log.notice("window picker cursor \(self.screenshotGuard.windowPicker.description, privacy: .public)")
        // Keep App Nap from throttling the growth timer while still allowing idle sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Growing mould"
        )
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildOverlays() }
        }
        rebuildOverlays()
        lastTick = CACurrentMediaTime()
        scheduleTimer()
    }

    var progress: Double { clock.progress(duration: Self.duration) }
    var minutesAtScreen: Double { clock.elapsed / max(clock.speed, 0.001) / 60 }
    var isWiping: Bool { wipe != nil }
    var isAway: Bool { pausesWhenAway && Self.secondsSinceLastInput() >= clock.idleThreshold }

    /// The hotkey: wipe the screen clean with a satisfying sweep, then start over.
    func wipeOff() {
        guard wipe == nil else { return }
        guard !simulations.values.allSatisfy({ $0.colonies(at: clock.elapsed).isEmpty }) else {
            reset()
            return
        }
        wipe = WipeAnimation()
        scheduleTimer()
        onStateChange?()
    }

    /// Start over, instantly (lock screen, screensaver, sleep...).
    func reset() {
        wipe = nil
        clock.reset()
        seed = .random(in: 1...UInt64.max)
        replant()
        redraw()
        scheduleTimer()
        onStateChange?()
    }

    // MARK: - Screens

    private func rebuildOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let window = OverlayWindow(screen: screen, renderer: renderer)
            let id = window.displayID
            window.mouldView.frameProvider = { [weak self, weak window] in
                guard let self, let window else { return nil }
                return self.frame(for: id, window: window)
            }
            window.orderFrontRegardless()
            return window
        }
        replant()
        redraw()
    }

    private func replant() {
        simulations = [:]
        for window in overlays {
            let size = window.frame.size
            // Each screen gets its own pattern, but the same seed keeps them stable across rebuilds.
            simulations[window.displayID] = MouldSimulation(
                width: size.width, height: size.height,
                seed: seed &+ UInt64(window.displayID) &* 0x9E37_79B9,
                theme: theme, duration: Self.duration
            )
        }
    }

    private func frame(for id: CGDirectDisplayID, window: NSWindow) -> MouldFrame? {
        guard let sim = simulations[id] else { return nil }
        return MouldFrame(
            colonies: sim.colonies(at: clock.elapsed),
            widthPoints: window.frame.width, heightPoints: window.frame.height,
            scale: window.backingScaleFactor, theme: theme, opacity: opacity,
            wipe: wipe?.progress, time: clock.elapsed
        )
    }

    // MARK: - Loop

    private func scheduleTimer() {
        let interval = RedrawPolicy.interval(speed: clock.speed, wiping: wipe != nil)
        guard interval != timerInterval || timer == nil else { return }
        timer?.invalidate()
        timerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now

        if var active = wipe {
            active.advance(by: dt)
            wipe = active
            redraw()
            if active.isFinished { reset() }
            return
        }

        clock.advance(by: dt, idleFor: pausesWhenAway ? Self.secondsSinceLastInput() : 0)
        // Not while ⌘⇧4's crosshair is up: a redraw could hold up stepping aside for the picker.
        if clock.elapsed != lastDrawnElapsed && !screenshotGuard.awaitingSpace { redraw() }
    }

    private func redraw() {
        lastDrawnElapsed = clock.elapsed
        overlays.forEach { $0.mouldView.draw() }
        updateVisibility()
    }

    // MARK: - Screenshots

    /// macOS's window picker (⌘⇧4, Space) settles on the topmost non-transparent window under the pointer
    /// within milliseconds, so the overlays turn transparent as Space goes down; see `ScreenshotDetection`.
    /// They are also transparent while there is nothing to show.
    private func updateVisibility() {
        let aside = hidesDuringScreenshots && screenshotGuard.shouldStepAside(at: CACurrentMediaTime())
        // Out of the way first: the picker doesn't wait.
        let alpha: CGFloat = !aside && hasMould ? 1 : 0
        for window in overlays where window.alphaValue != alpha {
            window.alphaValue = alpha
        }
        if aside != steppedAside {
            steppedAside = aside
            log.notice("\(aside ? "stepping aside for a screenshot" : "back after the screenshot", privacy: .public)")
        }

        // Watch the pointer and keyboard while there is mould in the picker's way, or while stepping aside.
        let shouldWatch = hidesDuringScreenshots && (alpha > 0 || aside)
        scheduleCaptureTimer(interval: shouldWatch ? screenshotGuard.pollInterval : nil)
    }

    private var hasMould: Bool {
        wipe != nil || simulations.values.contains { !$0.colonies(at: clock.elapsed).isEmpty }
    }

    private func scheduleCaptureTimer(interval: TimeInterval?) {
        guard interval != captureTimer?.timeInterval else { return }
        captureTimer?.invalidate()
        captureTimer = nil
        guard let interval else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForScreenshot() }
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer
    }

    /// The window picker's camera as this macOS draws it: the system's "screenshotwindow" cursor.
    private static func windowPickerCursor() -> CursorShape {
        let folder = URL(fileURLWithPath: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Resources/cursors/screenshotwindow")
        guard let info = NSDictionary(contentsOf: folder.appendingPathComponent("info.plist")),
              let hotX = (info["hotx"] as? NSNumber)?.doubleValue, let hotY = (info["hoty"] as? NSNumber)?.doubleValue,
              let size = NSImage(contentsOf: folder.appendingPathComponent("cursor.pdf"))?.size, size.width > 0
        else { return ScreenshotDetection.windowPickerCursor }
        return CursorShape(width: size.width, height: size.height, hotX: hotX, hotY: hotY)
    }

    /// The pointer as the system shows it, whichever app set it.
    private static func systemCursorShape() -> CursorShape? {
        guard let cursor = NSCursor.currentSystem else { return nil }
        return CursorShape(width: cursor.image.size.width, height: cursor.image.size.height, hotX: cursor.hotSpot.x, hotY: cursor.hotSpot.y)
    }

    private func pollForScreenshot() {
        let now = CACurrentMediaTime()
        // None of these needs Accessibility or Input Monitoring permission.
        let lastKeyDown = now - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        screenshotGuard.observe(
            cursor: Self.systemCursorShape(), mouseDown: NSEvent.pressedMouseButtons != 0, lastKeyDown: lastKeyDown, at: now
        )
        if hidesDuringScreenshots && screenshotGuard.shouldStepAside(at: now) != steppedAside {
            updateVisibility()
        } else {
            scheduleCaptureTimer(interval: screenshotGuard.pollInterval)
        }
    }

    private func applyClockSettings() {
        clock.speed = speed
        clock.idleThreshold = pausesWhenAway ? 5 * 60 : .infinity
    }

    static func secondsSinceLastInput() -> TimeInterval {
        // kCGAnyInputEventType
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

/// Persisted preferences.
@MainActor
enum Settings {
    private static let defaults = UserDefaults.standard

    static var theme: Theme {
        get { Theme(rawValue: UInt32(defaults.integer(forKey: "theme"))) ?? .orange }
        set { defaults.set(Int(newValue.rawValue), forKey: "theme") }
    }

    static var opacity: Double {
        get { defaults.object(forKey: "opacity") as? Double ?? 0.92 }
        set { defaults.set(newValue, forKey: "opacity") }
    }

    static var hidesDuringScreenshots: Bool {
        get { defaults.object(forKey: "hidesDuringScreenshots") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "hidesDuringScreenshots") }
    }

    static var pausesWhenAway: Bool {
        get { defaults.object(forKey: "pausesWhenAway") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "pausesWhenAway") }
    }
}
