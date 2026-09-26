import Foundation
import Metal
import Testing
@testable import MouldCore
@testable import MouldRender
/// Prints GPU time per frame at MacBook Retina size. Run with: PROBE=1 swift test --filter perfProbe
@Test func perfProbe() throws {
    guard ProcessInfo.processInfo.environment["PROBE"] != nil else { return }
    let r = try MouldRenderer()
    print("PROBE gpu", r.device.name)
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 3024, height: 1964, mipmapped: false)
    d.usage = .renderTarget; d.storageMode = .private
    let tex = r.device.makeTexture(descriptor: d)!
    for theme in [Theme.orange, .strawberry] {
    for m in [20.0, 45, 75] {
        let sim = MouldSimulation(width: 1512, height: 982, seed: 3, theme: theme)
        let f = MouldFrame(colonies: sim.colonies(at: m * 60), widthPoints: 1512, heightPoints: 982, scale: 2, theme: theme)
        var total = 0.0
        for k in 0..<6 {
            let cb = r.commandQueue.makeCommandBuffer()!
            let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = tex
            r.encode(f, commandBuffer: cb, pass: pass)
            cb.commit(); cb.waitUntilCompleted()
            if k > 0 { total += cb.gpuEndTime - cb.gpuStartTime }
        }
        print("PROBE", theme, m, "min", Int(total / 5 * 1000), "ms GPU/frame @3024x1964")
    }
    }
}
