import AppKit
import MouldCore
import MouldRender

let options: LaunchOptions
do {
    options = try LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("mould: \(error)\n\n\(LaunchOptions.usage)\n".utf8))
    exit(64)
}

if options.showHelp {
    print(LaunchOptions.usage)
    exit(0)
}

if let path = options.iconPath {
    exit(SnapshotCommand.icon(path: path))
}

if let path = options.snapshotPath {
    exit(SnapshotCommand.run(options, path: path))
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate(options: options)
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
