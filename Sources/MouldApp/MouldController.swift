import AppKit
import Darwin
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
    private var screenshotGuard = ScreenshotGuard()
    private var steppedAside = false
    private var screenshotPolls = 0

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
        if clock.elapsed != lastDrawnElapsed { redraw() }
    }

    private func redraw() {
        lastDrawnElapsed = clock.elapsed
        overlays.forEach { $0.mouldView.draw() }
        updateVisibility()
    }

    // MARK: - Screenshots

    /// macOS's window picker (⌘⇧4, Space) takes the topmost non-transparent pixel under the pointer and
    /// snapshots that choice when it opens, so the overlays must already be transparent by then; see
    /// `ScreenshotDetection`. They are also transparent while there is nothing to show.
    private func updateVisibility() {
        let hasMould = wipe != nil || simulations.values.contains { !$0.colonies(at: clock.elapsed).isEmpty }
        let aside = hidesDuringScreenshots && screenshotGuard.shouldStepAside(at: CACurrentMediaTime())
        if aside != steppedAside {
            steppedAside = aside
            log.notice("\(aside ? "stepping aside for a screenshot" : "back after the screenshot", privacy: .public)")
        }
        let alpha: CGFloat = hasMould && !aside ? 1 : 0
        for window in overlays where window.alphaValue != alpha {
            window.alphaValue = alpha
        }

        // Watch the keyboard while there is mould in the picker's way, or while stepping aside.
        let shouldWatch = hidesDuringScreenshots && (hasMould || aside)
        if shouldWatch, captureTimer == nil {
            let timer = Timer(timeInterval: ScreenshotDetection.modifierPollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollForScreenshot() }
            }
            RunLoop.main.add(timer, forMode: .common)
            captureTimer = timer
        } else if !shouldWatch, let timer = captureTimer {
            timer.invalidate()
            captureTimer = nil
        }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = pid > 0 ? proc_pidpath(pid, &buffer, UInt32(buffer.count)) : 0
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }

    private func pollForScreenshot() {
        let now = CACurrentMediaTime()
        // System-wide modifier state; reading it needs no Accessibility or Input Monitoring permission.
        let flags = NSEvent.modifierFlags
        screenshotGuard.observe(commandShiftHeld: flags.contains(.command) && flags.contains(.shift), at: now)
        if steppedAside {
            screenshotGuard.observe(mouseDown: NSEvent.pressedMouseButtons != 0, at: now)
        }

        // The window list is pricier (~2 ms), and only needed to see when a screenshot UI goes away.
        screenshotPolls += 1
        if steppedAside && screenshotPolls % ScreenshotDetection.windowPollEvery == 0 {
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let capturing = ScreenshotDetection.isCapturing(windowOwners: windows.lazy.map { window in
                ScreenshotDetection.WindowOwner(
                    name: window[kCGWindowOwnerName as String] as? String ?? "",
                    executablePath: Self.executablePath(of: window[kCGWindowOwnerPID as String] as? pid_t ?? 0)
                )
            })
            if capturing != screenshotGuard.captureWindowsVisible {
                log.notice("capture windows \(capturing ? "appeared" : "gone", privacy: .public)")
            }
            screenshotGuard.observe(captureWindowsVisible: capturing)
        }
        if hidesDuringScreenshots && screenshotGuard.shouldStepAside(at: now) != steppedAside {
            updateVisibility()
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
