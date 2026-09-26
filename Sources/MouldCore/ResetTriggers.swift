/// Moments that mean "the user stepped away from the screen", after which the mould starts over.
public enum ResetTrigger: String, CaseIterable, Sendable {
    case screenLocked
    case screenSaverStarted
    case displaysSlept
    case systemSleep
    case sessionSwitchedAway

    /// Distributed notifications posted by loginwindow / ScreenSaverEngine.
    public var distributedNotificationName: String? {
        switch self {
        case .screenLocked: "com.apple.screenIsLocked"
        case .screenSaverStarted: "com.apple.screensaver.didstart"
        default: nil
        }
    }

    /// NSWorkspace notification names (raw values, so this target stays AppKit-free).
    public var workspaceNotificationName: String? {
        switch self {
        case .displaysSlept: "NSWorkspaceScreensDidSleepNotification"
        case .systemSleep: "NSWorkspaceWillSleepNotification"
        case .sessionSwitchedAway: "NSWorkspaceSessionDidResignActiveNotification"
        default: nil
        }
    }
}
