import CoreGraphics
import Foundation
import Metal
import MouldCore
import simd

/// Everything the shader needs for one frame.
public struct MouldFrame: Sendable {
    public var colonies: [ColonyState]
    public var widthPoints: Double
    public var heightPoints: Double
    public var scale: Double
    public var theme: Theme
    public var opacity: Double
    /// Wipe front 0...1 while the clear animation runs, nil otherwise.
    public var wipe: Double?
    public var time: Double

    public init(
        colonies: [ColonyState], widthPoints: Double, heightPoints: Double, scale: Double,
        theme: Theme, opacity: Double = 0.92, wipe: Double? = nil, time: Double = 0
    ) {
        self.colonies = colonies
        self.widthPoints = widthPoints
        self.heightPoints = heightPoints
        self.scale = scale
        self.theme = theme
        self.opacity = opacity
        self.wipe = wipe
        self.time = time
    }
}

public enum MouldRendererError: Error {
    case noMetalDevice
    case missingFunction(String)
    case textureCreationFailed
}

/// Draws mould with a single full-screen fragment shader.
public final class MouldRenderer: @unchecked Sendable {
    public static let pixelFormat = MTLPixelFormat.bgra8Unorm

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    /// One row of `AngularProfile` per colony slot, refreshed only when a slot's colony changes.
    private let profiles: MTLTexture
    private var profileSeeds: [Double?] = Array(repeating: nil, count: MouldSimulation.maxColonies)
    private let lock = NSLock()

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw MouldRendererError.noMetalDevice }
        self.device = device
        self.commandQueue = queue
        let library = try device.makeLibrary(source: MouldShader.source, options: nil)
        guard let vertex = library.makeFunction(name: MouldShader.vertexFunction) else {
            throw MouldRendererError.missingFunction(MouldShader.vertexFunction)
        }
        guard let fragment = library.makeFunction(name: MouldShader.fragmentFunction) else {
            throw MouldRendererError.missingFunction(MouldShader.fragmentFunction)
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Mould"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = Self.pixelFormat
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let profileDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: AngularProfile.samples, height: MouldSimulation.maxColonies, mipmapped: false
        )
        profileDesc.usage = .shaderRead
        guard let profiles = device.makeTexture(descriptor: profileDesc) else { throw MouldRendererError.textureCreationFailed }
        self.profiles = profiles
    }

    private func updateProfiles(for colonies: ArraySlice<ColonyState>) {
        for (row, colony) in colonies.enumerated() where profileSeeds[row] != colony.noiseSeed {
            var values = AngularProfile.make(seed: colony.noiseSeed)
            profiles.replace(
                region: MTLRegionMake2D(0, row, AngularProfile.samples, 1), mipmapLevel: 0,
                withBytes: &values, bytesPerRow: AngularProfile.samples * MemoryLayout<SIMD4<Float>>.stride
            )
            profileSeeds[row] = colony.noiseSeed
        }
    }

    /// Encodes one frame into `pass`, which should clear to transparent.
    public func encode(_ frame: MouldFrame, commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor) {
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        defer { encoder.endEncoding() }

        var packed = Self.pack(frame)
        guard packed.count > 0 else { return }
        lock.lock()
        updateProfiles(for: frame.colonies.prefix(MouldSimulation.maxColonies))
        lock.unlock()
        var uniforms = Self.uniforms(for: frame, colonyCount: packed.count)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GPUUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&packed, length: MemoryLayout<GPUColony>.stride * packed.count, index: 1)
        encoder.setFragmentTexture(profiles, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Renders offscreen and returns a premultiplied sRGB image (for snapshots, icons and tests).
    public func renderImage(_ frame: MouldFrame) throws -> CGImage {
        let width = max(1, Int((frame.widthPoints * frame.scale).rounded()))
        let height = max(1, Int((frame.heightPoints * frame.scale).rounded()))
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: Self.pixelFormat, width: width, height: height, mipmapped: false
        )
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: texDesc),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw MouldRendererError.textureCreationFailed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        encode(frame, commandBuffer: commandBuffer, pass: pass)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        texture.getBytes(&bytes, bytesPerRow: bytesPerRow, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else {
            throw MouldRendererError.textureCreationFailed
        }
        return image
    }

    // MARK: - GPU layout (must match the structs in MouldShader)

    struct GPUUniforms {
        var view: SIMD4<Float>
        var params: SIMD4<Float>
    }

    struct GPUColony {
        var a: SIMD4<Float>
        var b: SIMD4<Float>
        var c: SIMD4<Float>
    }

    static func uniforms(for frame: MouldFrame, colonyCount: Int) -> GPUUniforms {
        GPUUniforms(
            view: SIMD4(Float(frame.widthPoints), Float(frame.heightPoints), Float(frame.scale), Float(frame.time)),
            params: SIMD4(Float(frame.wipe ?? -1), Float(frame.opacity), Float(colonyCount), Float(frame.theme.rawValue))
        )
    }

    static func pack(_ frame: MouldFrame) -> [GPUColony] {
        frame.colonies.prefix(MouldSimulation.maxColonies).map { c in
            GPUColony(
                a: SIMD4(Float(c.x), Float(c.y), Float(c.radius), Float(c.maturity)),
                b: SIMD4(Float(c.species.rawValue), Float(c.noiseSeed), Float(c.sporeRadius), Float(c.stretch)),
                c: SIMD4(Float(c.angle), Float(cos(c.angle)), Float(sin(c.angle)), 0)
            )
        }
    }
}

