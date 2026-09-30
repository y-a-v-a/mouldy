/// Spotting macOS's own screenshot tools, so the mould can step aside for them.
///
/// ⌘⇧4 + Space picks "the window under the pointer": the topmost window whose pixel there isn't
/// transparent, whatever its level or sharing type. The picker is a separate process, started when Space is
/// pressed, and it decides once, early on; clicking a window that turned transparent only after that fails
/// with "Unable to capture window image". Stepping aside the moment Space is pressed is soon enough.
///
/// The keys themselves can't be seen without Input Monitoring, but the pointer gives the mode away: ⌘⇧4
/// turns it into a crosshair, and Space into a camera. So a screenshot session is a `screencaptureui`
/// window on screen after the system cursor changed while ⌘⇧ were held (the first new cursor is the
/// crosshair), and Mould steps aside while the pointer is anything but that crosshair. The mould stays in
/// ⌘⇧3 captures (no new cursor, even though its floating thumbnail comes with an identical window) and in
/// ⌘⇧4 region captures.
///
/// Watching the window list all the time would cost too much CPU. Every screenshot shortcut starts with ⌘⇧
/// held down, and the modifier state can be read cheaply and without permissions. So Mould only looks for
/// the screenshot UI while ⌘⇧ are held, and briefly after they are released.
public enum ScreenshotDetection {
    /// The app behind ⌘⇧3/4/5. Its crosshair overlay is a full-screen window whose owner is called
    /// "Screenshot" (localised), so it is recognised by its executable's path rather than by name.
    public static let captureAppBundleName = "screencaptureui.app"
    /// The command-line tool (`screencapture -i`), which has no bundle; it owns the "windowselection" window.
    public static let captureToolName = "screencapture"

    /// Modifier polling: fast enough not to miss even a quick ⌘⇧4. The same timer checks the (pricier,
    /// ~2 ms) window list, but only while `ScreenshotGuard.isWatching`.
    public static let pollInterval: Double = 1.0 / 30

    public struct WindowOwner: Sendable, Equatable {
        public var name: String
        public var executablePath: String?
        public init(name: String, executablePath: String?) {
            self.name = name
            self.executablePath = executablePath
        }
    }

    public static func isCapturing(windowOwners: some Sequence<WindowOwner>) -> Bool {
        windowOwners.contains { owner in
            owner.executablePath?.contains("/\(captureAppBundleName)/") == true || owner.name.lowercased() == captureToolName
        }
    }
}

/// Decides when the mould should be out of the way of a screenshot.
public struct ScreenshotGuard: Sendable, Equatable {
    /// After ⌘⇧ are released, keep looking for the screenshot UI this long.
    public var watchAfterRelease: Double
    /// After the capturing click, come back this much later, even though the screenshot UI lingers while
    /// its thumbnail floats in the corner.
    public var afterCapture: Double
    private var shortcutHeld = false
    private var releasedAt: Double?
    private var cursor = ""
    private var cursorBeforeShortcut: String?
    private var crosshair: String?
    private var mouseWasDown = false
    private var capturedAt: Double?
    private var asideAtCapture = false
    public private(set) var captureWindowsVisible = false

    public init(watchAfterRelease: Double = 1, afterCapture: Double = 4) {
        self.watchAfterRelease = watchAfterRelease
        self.afterCapture = afterCapture
    }

    /// Feed the live state of ⌘ and ⇧ (both held = a screenshot shortcut may be coming), along with a
    /// fingerprint of the system cursor.
    public mutating func observe(commandShiftHeld held: Bool, cursor newCursor: String, at time: Double) {
        if shortcutHeld && !held { releasedAt = time }
        if !shortcutHeld && held {
            // A new screenshot, maybe while the last thumbnail floats. Compare with the pointer from just
            // before, since a quick ⌘⇧4 can show the crosshair by the time ⌘⇧ is first seen.
            cursorBeforeShortcut = cursor
            crosshair = nil
            capturedAt = nil
        }
        shortcutHeld = held
        if crosshair == nil, capturedAt == nil, isWatching(at: time),
           let cursorBeforeShortcut, newCursor != cursorBeforeShortcut {
            crosshair = newCursor
        }
        cursor = newCursor
    }

    /// Feed the live mouse button state: a capture ends when the button goes up while the UI is on screen.
    public mutating func observe(mouseDown down: Bool, at time: Double) {
        if captureWindowsVisible && mouseWasDown && !down && capturedAt == nil {
            asideAtCapture = shouldStepAside(at: time)
            capturedAt = time
        }
        mouseWasDown = down
    }

    public mutating func observe(captureWindowsVisible visible: Bool) {
        if !visible {
            cursorBeforeShortcut = nil
            crosshair = nil
            capturedAt = nil
        }
        captureWindowsVisible = visible
    }

    /// Whether the window list is worth checking: a screenshot UI may be about to appear, or is up.
    public func isWatching(at time: Double) -> Bool {
        if shortcutHeld || captureWindowsVisible { return true }
        guard let releasedAt else { return false }
        return time - releasedAt < watchAfterRelease
    }

    public func shouldStepAside(at time: Double) -> Bool {
        guard captureWindowsVisible, let crosshair else { return false }
        // After a capture the choice holds: back a little later after a window, still there after a region.
        if let capturedAt { return asideAtCapture && time - capturedAt < afterCapture }
        return cursor != crosshair
    }
}
