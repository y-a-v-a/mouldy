/// Spotting macOS's window picker, so the mould can step aside for it.
///
/// ⌘⇧4 + Space picks "the window under the pointer": the topmost window that isn't transparent, whatever
/// its level or sharing type. The picker takes stock of the windows as Space goes down; clicking a window
/// that turned transparent only after that fails with "Unable to capture window image".
///
/// The keys themselves can't be seen without Input Monitoring, but the pointer gives window mode away: it
/// turns into a camera, the system's "screenshotwindow" cursor. So Mould steps aside while the system cursor
/// has the camera's size and hot spot, and nothing else counts: not ⌘⇧3, not ⌘⇧4's crosshair, and not the
/// shapes the pointer takes as it moves over text, links and window edges.
///
/// The picker can settle on its window within milliseconds of the camera showing, and doesn't reconsider
/// when the mould fades later, not even as the pointer moves. So Mould goes when a key goes down while the
/// crosshair is up: that can only be Space or Esc, and when a key last went down can be read without
/// permission. Both are watched every millisecond while the crosshair is up, at a relaxed pace otherwise.
public enum ScreenshotDetection {
    /// The camera as macOS 26 draws it (HIServices' `cursors/screenshotwindow`), for when the system's own
    /// copy can't be read.
    public static let windowPickerCursor = CursorShape(width: 28, height: 25, hotX: 14, hotY: 11)
    /// ⌘⇧4's crosshair (`cursors/screenshotselection`). On screen it is wider and taller, as it prints the
    /// pointer's coordinates to the right of and below the hot spot.
    public static let regionPickerCursor = CursorShape(width: 32, height: 32, hotX: 15, hotY: 15)

    /// Pointer polling; a look costs ~55 µs.
    public static let pollInterval: Double = 1.0 / 30
    /// While the crosshair is up, Space may come any moment.
    public static let crosshairPollInterval: Double = 1.0 / 1000
}

/// A pointer's size and hot spot, in points: enough to tell the system's cursors apart.
public struct CursorShape: Sendable, Equatable, CustomStringConvertible {
    public var width: Double
    public var height: Double
    public var hotX: Double
    public var hotY: Double

    public init(width: Double, height: Double, hotX: Double, hotY: Double) {
        self.width = width
        self.height = height
        self.hotX = hotX
        self.hotY = hotY
    }

    /// Whether this is `other` at some size: Accessibility's pointer size and shake-to-locate enlarge the
    /// pointer, hot spot and all, give or take some rounding.
    public func isScaled(_ other: CursorShape) -> Bool {
        guard width > 0, other.width > 0 else { return false }
        let scale = width / other.width
        let slack = max(scale, 1) / 2
        return abs(height - other.height * scale) <= slack
            && abs(hotX - other.hotX * scale) <= slack
            && abs(hotY - other.hotY * scale) <= slack
    }

    /// Whether this is `other` at its size or larger, perhaps with more drawn to the right and below.
    public func extends(_ other: CursorShape) -> Bool {
        guard other.hotX > 0 else { return false }
        let scale = hotX / other.hotX
        let slack = max(scale, 1) / 2
        return scale > 0.95 && abs(hotY - other.hotY * scale) <= slack
            && width >= other.width * scale - slack
            && height >= other.height * scale - slack
    }

    public var description: String { "\(width)x\(height)@\(hotX),\(hotY)" }
}

/// Decides when the mould should be out of the way of a screenshot.
public struct ScreenshotGuard: Sendable, Equatable {
    /// The window picker's camera, as this Mac draws it.
    public var windowPicker: CursorShape
    public var regionPicker: CursorShape
    /// After a window is clicked, come back this much later.
    public var afterCapture: Double
    private var picking = false
    private var crosshairSince: Double?
    private var lastKeyDown = -Double.infinity
    private var keyedInCrosshair = false
    private var pressedWhilePicking = false
    private var capturedAt: Double?

    public init(
        windowPicker: CursorShape = ScreenshotDetection.windowPickerCursor,
        regionPicker: CursorShape = ScreenshotDetection.regionPickerCursor,
        afterCapture: Double = 4
    ) {
        self.windowPicker = windowPicker
        self.regionPicker = regionPicker
        self.afterCapture = afterCapture
    }

    /// ⌘⇧4's crosshair is up: Space, and the picker, may follow any moment.
    public var awaitingSpace: Bool { crosshairSince != nil }

    /// How soon to look again.
    public var pollInterval: Double {
        awaitingSpace ? ScreenshotDetection.crosshairPollInterval : ScreenshotDetection.pollInterval
    }

    /// Feed the system cursor, the mouse buttons and when a key last went down (which key can't be seen
    /// without Input Monitoring), poll by poll.
    public mutating func observe(cursor: CursorShape?, mouseDown: Bool, lastKeyDown keyDown: Double, at time: Double) {
        picking = cursor?.isScaled(windowPicker) == true
        if cursor?.extends(regionPicker) == true {
            if crosshairSince == nil {
                crosshairSince = time
                keyedInCrosshair = false
            }
        } else {
            crosshairSince = nil
        }
        // A key in the crosshair is Space or Esc, which both end it; Space goes on to the picker, which
        // settles a few milliseconds after the camera shows, so this is the moment to go. (Space held while
        // dragging moves the selection instead, and ⌘⇧4's own 4 went down before the crosshair came up.)
        if keyDown > lastKeyDown {
            lastKeyDown = keyDown
            if let crosshairSince, keyDown > crosshairSince, !mouseDown { keyedInCrosshair = true }
        }

        if mouseDown && picking { pressedWhilePicking = true }
        if !mouseDown && pressedWhilePicking {
            pressedWhilePicking = false
            capturedAt = time
        }
    }

    public func shouldStepAside(at time: Double) -> Bool {
        if picking || (awaitingSpace && keyedInCrosshair) { return true }
        guard let capturedAt else { return false }
        return time - capturedAt < afterCapture
    }
}
