import CoreGraphics
import Foundation
import Metal
import Testing
@testable import MouldCore
@testable import MouldRender

/// These run the real shader on the GPU and inspect the pixels.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct MouldRendererTests {
    let renderer: MouldRenderer

    init() throws {
        renderer = try MouldRenderer()
    }

    static let width = 480.0, height = 300.0

    func render(minutes: Double, theme: Theme = .orange, wipe: Double? = nil, seed: UInt64 = 1) throws -> CGImage {
        let sim = MouldSimulation(width: Self.width, height: Self.height, seed: seed, theme: theme)
        let frame = MouldFrame(
            colonies: sim.colonies(at: minutes * 60), widthPoints: Self.width, heightPoints: Self.height,
            scale: 1, theme: theme, opacity: 0.92, wipe: wipe
        )
        return try renderer.renderImage(frame)
    }

    /// Fraction of pixels with alpha above `threshold`, and the max alpha seen.
    func alphaStats(_ image: CGImage, threshold: UInt8 = 64) -> (covered: Double, maxAlpha: UInt8) {
        let data = image.dataProvider!.data! as Data
        var covered = 0, maxAlpha: UInt8 = 0
        let pixels = image.width * image.height
        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            for i in 0..<pixels {
                let row = i / image.width, col = i % image.width
                let a = bytes[row * image.bytesPerRow + col * 4 + 3] // BGRA
                if a > threshold { covered += 1 }
                maxAlpha = max(maxAlpha, a)
            }
        }
        return (Double(covered) / Double(pixels), maxAlpha)
    }

    @Test func gpuStructLayoutMatchesShader() {
        #expect(MemoryLayout<MouldRenderer.GPUColony>.stride == 48)
        #expect(MemoryLayout<MouldRenderer.GPUUniforms>.stride == 32)
    }

    @Test func freshScreenIsCompletelyClear() throws {
        let image = try render(minutes: 0)
        #expect(alphaStats(image, threshold: 0).maxAlpha == 0)
    }

    @Test func anHourLaterTheScreenIsClaimed() throws {
        let early = alphaStats(try render(minutes: 12)).covered
        let half = alphaStats(try render(minutes: 30)).covered
        let hour = alphaStats(try render(minutes: 60)).covered
        #expect(early < half)
        #expect(half < hour)
        #expect(hour > 0.75, "coverage after an hour: \(hour)")
    }

    @Test func mouldStaysPartlyTransparent() throws {
        let stats = alphaStats(try render(minutes: 60))
        #expect(stats.maxAlpha < 255, "never fully opaque, so the screen still shows through")
        #expect(stats.maxAlpha > 180)
    }

    @Test func finishedWipeLeavesNothingBehind() throws {
        let midway = alphaStats(try render(minutes: 60, wipe: 0.5)).covered
        let done = alphaStats(try render(minutes: 60, wipe: 1)).covered
        let before = alphaStats(try render(minutes: 60)).covered
        #expect(midway < before)
        #expect(done == 0)
    }

    @Test(arguments: Theme.allCases)
    func everyThemeGrows(theme: Theme) throws {
        let covered = alphaStats(try render(minutes: 45, theme: theme)).covered
        #expect(covered > 0.3, "\(theme) coverage \(covered)")
    }

    @Test func orangeMouldIsGreenAndStrawberryMouldIsGrey() throws {
        func meanColour(_ image: CGImage) -> (r: Double, g: Double, b: Double) {
            let data = image.dataProvider!.data! as Data
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for row in stride(from: 0, to: image.height, by: 2) {
                    for col in stride(from: 0, to: image.width, by: 2) {
                        let o = row * image.bytesPerRow + col * 4
                        let a = Double(bytes[o + 3])
                        guard a > 200 else { continue }
                        // un-premultiply
                        b += Double(bytes[o]) / a; g += Double(bytes[o + 1]) / a; r += Double(bytes[o + 2]) / a; n += 1
                    }
                }
            }
            return (r / n, g / n, b / n)
        }
        let orange = meanColour(try render(minutes: 60, theme: .orange))
        #expect(orange.g > orange.r && orange.g > orange.b, "Penicillium should read green: \(orange)")
        let berry = meanColour(try render(minutes: 60, theme: .strawberry))
        #expect(abs(berry.r - berry.g) < 0.08 && abs(berry.g - berry.b) < 0.1, "Botrytis should read grey: \(berry)")
    }
}
