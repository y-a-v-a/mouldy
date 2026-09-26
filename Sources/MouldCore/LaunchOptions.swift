import Foundation

/// Command-line options. The app normally runs with none; the rest is for demos and snapshots.
public struct LaunchOptions: Equatable, Sendable {
    /// Growth speed multiplier (`--speed 60` grows the full hour in one minute).
    public var speed: Double = 1
    public var theme: Theme?
    /// Start as if this many minutes had already passed (`--minutes 40`).
    public var startMinutes: Double = 0
    public var snapshotPath: String?
    public var snapshotWidth: Double = 1512
    public var snapshotHeight: Double = 982
    public var snapshotScale: Double = 2
    public var snapshotMinutes: Double = 45
    public var seed: UInt64?
    public var background: String?
    public var wipe: Double?
    public var showHelp = false
    /// Render the 1024px app icon to this path and exit (used by the build script).
    public var iconPath: String?

    public init() {}

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missingValue(String)
        case badValue(String, String)
        case unknown(String)

        public var description: String {
            switch self {
            case .missingValue(let flag): "\(flag) needs a value"
            case .badValue(let flag, let value): "\(flag): can't use '\(value)'"
            case .unknown(let flag): "unknown option \(flag)"
            }
        }
    }

    public static let usage = """
    Usage: Mould [options]

      --speed <x>          grow x times faster (60 = the full hour in a minute)
      --minutes <m>        start with m minutes of growth already on screen
      --theme <name>       orange | strawberry | compost

    Snapshot mode (renders a PNG and exits):
      --snapshot <path>    write a PNG instead of starting the overlay
      --size <w>x<h>       canvas size in points (default 1512x982)
      --scale <s>          backing scale (default 2)
      --at <m>             minutes of growth to render (default 45)
      --seed <n>           random seed
      --background <png>   composite over this image
      --wipe <0...1>       freeze the clear animation at this point
    """

    public static func parse(_ arguments: [String]) throws -> LaunchOptions {
        var options = LaunchOptions()
        var it = arguments.makeIterator()

        func value(_ flag: String) throws -> String {
            guard let v = it.next() else { throw ParseError.missingValue(flag) }
            return v
        }
        func number(_ flag: String) throws -> Double {
            let raw = try value(flag)
            guard let d = Double(raw), d.isFinite, d >= 0 else { throw ParseError.badValue(flag, raw) }
            return d
        }

        while let arg = it.next() {
            switch arg {
            case "--speed":
                options.speed = try number(arg)
                guard options.speed > 0 else { throw ParseError.badValue(arg, "0") }
            case "--minutes": options.startMinutes = try number(arg)
            case "--theme":
                let raw = try value(arg)
                guard let theme = Theme(name: raw) else { throw ParseError.badValue(arg, raw) }
                options.theme = theme
            case "--snapshot": options.snapshotPath = try value(arg)
            case "--size":
                let raw = try value(arg)
                let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
                guard parts.count == 2, parts.allSatisfy({ $0 >= 16 }) else { throw ParseError.badValue(arg, raw) }
                options.snapshotWidth = parts[0]
                options.snapshotHeight = parts[1]
            case "--scale":
                options.snapshotScale = try number(arg)
                guard (0.25...4).contains(options.snapshotScale) else { throw ParseError.badValue(arg, "\(options.snapshotScale)") }
            case "--at": options.snapshotMinutes = try number(arg)
            case "--seed":
                let raw = try value(arg)
                guard let s = UInt64(raw) else { throw ParseError.badValue(arg, raw) }
                options.seed = s
            case "--background": options.background = try value(arg)
            case "--wipe": options.wipe = min(1, try number(arg))
            case "--icon": options.iconPath = try value(arg)
            case "-h", "--help": options.showHelp = true
            default:
                // Xcode / LaunchServices like to pass these; ignore them.
                if arg.hasPrefix("-NS") || arg.hasPrefix("-Apple") || arg.hasPrefix("-psn_") {
                    _ = arg.hasPrefix("-psn_") ? nil : it.next()
                    continue
                }
                throw ParseError.unknown(arg)
            }
        }
        return options
    }
}

extension Theme {
    public init?(name: String) {
        switch name.lowercased() {
        case "orange", "oranges", "citrus": self = .orange
        case "strawberry", "strawberries": self = .strawberry
        case "compost", "mixed", "all": self = .compost
        default: return nil
        }
    }
}
