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

    init(renderer: MouldRenderer, options: LaunchOptions) {
        self.renderer = renderer
        theme = options.theme ?? Settings.theme
        opacity = Settings.opacity
        pausesWhenAway = Settings.pausesWhenAway
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

    static var pausesWhenAway: Bool {
        get { defaults.object(forKey: "pausesWhenAway") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "pausesWhenAway") }
    }
}
