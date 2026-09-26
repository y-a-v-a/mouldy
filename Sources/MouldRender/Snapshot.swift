import CoreGraphics
import Foundation
import ImageIO
import MouldCore
import UniformTypeIdentifiers

/// Offscreen rendering to PNG: handy for eyeballing the shader without launching the overlay.
public enum Snapshot {
    public struct Options: Sendable {
        public var width: Double = 1512
        public var height: Double = 982
        public var scale: Double = 2
        public var minutes: Double = 45
        public var seed: UInt64 = 1
        public var theme: Theme = .orange
        public var opacity: Double = 0.92
        public var wipe: Double?
        public var background: URL?

        public init() {}
    }

    public static func render(_ options: Options, renderer: MouldRenderer) throws -> CGImage {
        let sim = MouldSimulation(width: options.width, height: options.height, seed: options.seed, theme: options.theme)
        let frame = MouldFrame(
            colonies: sim.colonies(at: options.minutes * 60),
            widthPoints: options.width, heightPoints: options.height, scale: options.scale,
            theme: options.theme, opacity: options.opacity, wipe: options.wipe
        )
        let mould = try renderer.renderImage(frame)
        let pixelWidth = mould.width, pixelHeight = mould.height

        guard let ctx = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw MouldRendererError.textureCreationFailed }
        let rect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        if let url = options.background,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let background = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            ctx.draw(background, in: rect)
        } else {
            drawStandInDesktop(ctx, rect: rect, scale: options.scale)
        }
        ctx.draw(mould, in: rect)
        return ctx.makeImage()!
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// A plausible desktop: wallpaper gradient, a window with some "text" lines.
    static func drawStandInDesktop(_ ctx: CGContext, rect: CGRect, scale: Double) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [CGColor(red: 0.18, green: 0.32, blue: 0.62, alpha: 1), CGColor(red: 0.62, green: 0.42, blue: 0.70, alpha: 1)]
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: rect.width, y: rect.height), options: [])
        let window = rect.insetBy(dx: rect.width * 0.12, dy: rect.height * 0.12)
        ctx.setFillColor(CGColor(gray: 0.98, alpha: 1))
        ctx.addPath(CGPath(roundedRect: window, cornerWidth: 12 * scale, cornerHeight: 12 * scale, transform: nil))
        ctx.fillPath()
        ctx.setFillColor(CGColor(gray: 0.8, alpha: 1))
        var y = window.maxY - 60 * scale
        var i = 0
        while y > window.minY + 30 * scale {
            let w = window.width * (0.4 + 0.5 * Double((i * 37) % 11) / 11)
            ctx.fill(CGRect(x: window.minX + 40 * scale, y: y, width: w, height: 8 * scale))
            y -= 22 * scale
            i += 1
        }
    }
}

extension Snapshot {
    /// The app icon: a squircle of orange peel, grown over by our own mould.
    public static func renderIcon(size: Int = 1024, renderer: MouldRenderer) throws -> CGImage {
        let s = Double(size)
        let sim = MouldSimulation(width: s, height: s, seed: 12, theme: .orange, duration: 3600)
        // Only a few big colonies, so it reads at small sizes.
        let colonies = sim.colonies(at: 30 * 60).map { c -> ColonyState in
            var c = c; c.radius *= 1.1; c.sporeRadius *= 1.1; return c
        }
        let mould = try renderer.renderImage(MouldFrame(
            colonies: colonies, widthPoints: s, heightPoints: s, scale: 1, theme: .orange, opacity: 1
        ))
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw MouldRendererError.textureCreationFailed }
        let inset = s * 0.1
        let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
        let shape = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(shape)
        ctx.setFillColor(CGColor(red: 0.96, green: 0.52, blue: 0.08, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let peel = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 1.0, green: 0.68, blue: 0.20, alpha: 1), CGColor(red: 0.90, green: 0.40, blue: 0.03, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(peel, startCenter: CGPoint(x: s * 0.38, y: s * 0.66), startRadius: 0,
                               endCenter: CGPoint(x: s * 0.5, y: s * 0.5), endRadius: s * 0.62, options: [.drawsAfterEndLocation])
        ctx.draw(mould, in: CGRect(x: 0, y: 0, width: s, height: s))
        ctx.restoreGState()
        return ctx.makeImage()!
    }
}
