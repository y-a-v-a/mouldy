import Foundation

/// A colony's outline wobble as a function of angle, precomputed once per colony so the shader
/// can look it up instead of evaluating noise for every pixel.
///
/// Built from random-phase harmonics, so it is seamless all the way around the circle.
public enum AngularProfile {
    public static let samples = 256

    /// Per angle: (big lobes, fine ragged lobes, spore-mass wobble, hyphal reach), the first three in -0.5...0.5
    /// and reach in 0...1.
    public static func make(seed: Double, samples: Int = samples) -> [SIMD4<Float>] {
        var rng = SeededRandom(seed: UInt64(seed * 1_000_000_007) &+ 0x5EED)
        func harmonics(_ range: ClosedRange<Int>, falloff: Double) -> [(k: Double, amp: Double, phase: Double)] {
            range.map { k in
                (Double(k), pow(Double(k), -falloff) * rng.double(in: 0.4...1.0), rng.double(in: 0...(2 * .pi)))
            }
        }
        let big = harmonics(2...7, falloff: 1.0)
        let fine = harmonics(8...40, falloff: 0.8)
        let wob = harmonics(2...9, falloff: 0.9)
        let reach = harmonics(20...70, falloff: 0.3)

        func series(_ h: [(k: Double, amp: Double, phase: Double)], _ theta: Double) -> Double {
            h.reduce(0) { $0 + $1.amp * sin($1.k * theta + $1.phase) }
        }
        func normalised(_ values: [Double]) -> [Double] {
            let peak = values.map(abs).max() ?? 1
            return values.map { peak > 0 ? $0 / peak * 0.5 : 0 }
        }

        let thetas = (0..<samples).map { Double($0) / Double(samples) * 2 * .pi - .pi }
        let a = normalised(thetas.map { series(big, $0) })
        let b = normalised(thetas.map { series(fine, $0) })
        let c = normalised(thetas.map { series(wob, $0) })
        let d = normalised(thetas.map { series(reach, $0) })
        return (0..<samples).map { i in
            SIMD4(Float(a[i]), Float(b[i]), Float(c[i]), Float(d[i] + 0.5))
        }
    }
}
