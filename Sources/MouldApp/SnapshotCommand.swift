import Foundation
import MouldCore
import MouldRender

enum SnapshotCommand {
    static func run(_ options: LaunchOptions, path: String) -> Int32 {
        do {
            let renderer = try MouldRenderer()
            var snap = Snapshot.Options()
            snap.width = options.snapshotWidth
            snap.height = options.snapshotHeight
            snap.scale = options.snapshotScale
            snap.minutes = options.snapshotMinutes
            snap.seed = options.seed ?? 1
            snap.theme = options.theme ?? .orange
            snap.wipe = options.wipe
            snap.background = options.background.map { URL(fileURLWithPath: $0) }
            let started = Date()
            let image = try Snapshot.render(snap, renderer: renderer)
            try Snapshot.writePNG(image, to: URL(fileURLWithPath: path))
            print(String(format: "wrote %@ (%dx%d, %.0f ms)", path, image.width, image.height, Date().timeIntervalSince(started) * 1000))
            return 0
        } catch {
            FileHandle.standardError.write(Data("mould: snapshot failed: \(error)\n".utf8))
            return 1
        }
    }

    static func icon(path: String) -> Int32 {
        do {
            let image = try Snapshot.renderIcon(renderer: try MouldRenderer())
            try Snapshot.writePNG(image, to: URL(fileURLWithPath: path))
            return 0
        } catch {
            FileHandle.standardError.write(Data("mould: icon failed: \(error)\n".utf8))
            return 1
        }
    }
}
