/// Spotting macOS's own screenshot tools, so the mould can step aside for them.
///
/// ⌘⇧4 + Space picks "the window under the pointer": the topmost window whose pixel there isn't
/// transparent, whatever its level or sharing type. The picker snapshots that when it opens and doesn't
/// look again, and `screencaptureui` isn't announced as an app launch, so reacting to the screenshot UI
/// is always too late (clicking then fails with "Unable to capture window image").
///
/// The one cue that comes early enough, and needs no permissions, is the modifier keys: ⌘⇧ are held
/// before the 4 (or 3/5) goes down. So Mould steps aside while ⌘⇧ are held, lingers briefly after they
/// are released so the screenshot UI has time to appear, and then stays aside while that UI is on screen.
public enum ScreenshotDetection {
    /// The app behind ⌘⇧3/4/5. Its crosshair overlay is a full-screen window whose owner is called
    /// "Screenshot" (localised), so it is recognised by its executable's path rather than by name.
    public static let captureAppBundleName = "screencaptureui.app"
    /// The command-line tool (`screencapture -i`), which has no bundle; it owns the "windowselection" window.
    public static let captureToolName = "screencapture"

    /// Modifier polling: fast enough to beat a quick ⌘⇧4 (the 4 follows ⌘⇧ by well over 33 ms).
    public static let modifierPollInterval: Double = 1.0 / 30
    /// While stepping aside, check the (pricier) window list every this many modifier polls.
    public static let windowPollEvery = 3

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
    /// After ⌘⇧ are released, stay aside this long so the screenshot UI can show up.
    public var releaseGrace: Double
    /// After the capturing click (or the end of a region drag), come back this much later, even though
    /// the screenshot UI lingers while its thumbnail floats in the corner.
    public var afterCapture: Double
    private var shortcutHeld = false
    private var releasedAt: Double?
    private var mouseWasDown = false
    private var capturedAt: Double?
    public private(set) var captureWindowsVisible = false

    public init(releaseGrace: Double = 0.6, afterCapture: Double = 4) {
        self.releaseGrace = releaseGrace
        self.afterCapture = afterCapture
    }

    /// Feed the live mouse button state: a capture ends when the button goes up while the UI is on screen.
    public mutating func observe(mouseDown down: Bool, at time: Double) {
        if captureWindowsVisible && mouseWasDown && !down && capturedAt == nil { capturedAt = time }
        mouseWasDown = down
    }

    /// Feed the live state of ⌘ and ⇧ (both held = a screenshot shortcut may be coming).
    public mutating func observe(commandShiftHeld held: Bool, at time: Double) {
        if shortcutHeld && !held { releasedAt = time }
        if !shortcutHeld && held { capturedAt = nil } // a new screenshot, maybe while the last thumbnail floats
        shortcutHeld = held
    }

    public mutating func observe(captureWindowsVisible visible: Bool) {
        if !visible { capturedAt = nil }
        captureWindowsVisible = visible
    }

    public func shouldStepAside(at time: Double) -> Bool {
        if shortcutHeld { return true }
        if captureWindowsVisible {
            guard let capturedAt else { return true }
            return time - capturedAt < afterCapture
        }
        guard let releasedAt else { return false }
        return time - releasedAt < releaseGrace
    }
}
