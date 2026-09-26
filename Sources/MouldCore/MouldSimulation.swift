import Foundation

/// A colony as planned at seeding time: where and when it lands, and how it will grow.
public struct ColonySeed: Sendable, Equatable {
    public var birth: TimeInterval          // seconds after the clock started
    public var x: Double                    // points, origin top-left
    public var y: Double
    public var species: Species
    public var growthRate: Double           // points per second once established
    public var lag: TimeInterval            // germination lag before steady radial growth
    public var maxRadius: Double
    public var margin: Double               // white mycelium margin width (points)
    public var sporulationDelay: TimeInterval
    public var stretch: Double              // ellipse aspect (>= 1)
    public var angle: Double                // ellipse orientation (radians)
    public var noiseSeed: Double            // 0..1, decorrelates per-colony noise in the shader
}

/// A colony at a particular moment, ready to hand to the renderer.
public struct ColonyState: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double               // outer edge of the mycelium
    public var sporeRadius: Double          // outer edge of the coloured spore mass (0 = none yet)
    public var maturity: Double             // 0...1, drives stains, sporangia and opacity
    public var species: Species
    public var stretch: Double
    public var angle: Double
    public var noiseSeed: Double
}

/// Deterministic mould growth: the entire state is a pure function of (seed, screen size, elapsed time).
///
/// Growth is tuned so that after `duration` (one hour by default) most of the screen is claimed:
/// nothing visible for the first couple of minutes, a few specks by ten minutes, fuzzy islands by half
/// an hour and a proper science experiment by the hour.
public struct MouldSimulation: Sendable {
    public static let maxColonies = 64

    public let width: Double
    public let height: Double
    public let duration: TimeInterval
    public let seeds: [ColonySeed]

    public init(width: Double, height: Double, seed: UInt64, theme: Theme, duration: TimeInterval = 3600) {
        self.width = width
        self.height = height
        self.duration = duration
        self.seeds = MouldSimulation.plant(width: width, height: height, seed: seed, theme: theme, duration: duration)
    }

    public var diagonal: Double { (width * width + height * height).squareRoot() }

    /// Colonies alive at `t` seconds, in birth order.
    public func colonies(at t: TimeInterval) -> [ColonyState] {
        seeds.compactMap { MouldSimulation.state(of: $0, at: t) }
    }

    public static func radius(of seed: ColonySeed, at t: TimeInterval) -> Double {
        let age = t - seed.birth
        guard age > 0 else { return 0 }
        // Quadratic start (germination) blending into linear radial growth, softly capped.
        let raw = seed.growthRate * age * age / (age + seed.lag)
        return seed.maxRadius * tanh(raw / seed.maxRadius)
    }

    static func state(of seed: ColonySeed, at t: TimeInterval) -> ColonyState? {
        let age = t - seed.birth
        guard age > 0 else { return nil }
        let r = radius(of: seed, at: t)
        guard r > 0.25 else { return nil }
        let maturity = min(1, max(0, age / (seed.sporulationDelay * 3)))
        let sporeProgress = smoothstep(seed.sporulationDelay * 0.5, seed.sporulationDelay * 1.5, age)
        let sporeRadius = max(0, r - seed.margin) * sporeProgress
        return ColonyState(
            x: seed.x, y: seed.y, radius: r, sporeRadius: sporeRadius, maturity: maturity,
            species: seed.species, stretch: seed.stretch, angle: seed.angle, noiseSeed: seed.noiseSeed
        )
    }

    /// Fraction of the screen covered by mycelium at `t`, estimated on a sample grid (ignores edge noise).
    public func coverage(at t: TimeInterval, samplesAcross: Int = 64) -> Double {
        let live = colonies(at: t)
        guard !live.isEmpty else { return 0 }
        let cols = samplesAcross
        let rows = max(1, Int(Double(cols) * height / width))
        var hit = 0
        for j in 0..<rows {
            for i in 0..<cols {
                let px = (Double(i) + 0.5) / Double(cols) * width
                let py = (Double(j) + 0.5) / Double(rows) * height
                if live.contains(where: { $0.contains(px, py) }) { hit += 1 }
            }
        }
        return Double(hit) / Double(rows * cols)
    }

    // MARK: - Planting

    static func plant(width: Double, height: Double, seed: UInt64, theme: Theme, duration: TimeInterval) -> [ColonySeed] {
        var rng = SeededRandom(seed: seed)
        let diag = (width * width + height * height).squareRoot()
        // Rates scale with the diagonal, so a fixed head-count keeps the story identical on every screen size.
        let count = 26
        let minute = duration / 60 // "minutes" scale with the duration so a 1-minute demo still looks right

        var planted: [ColonySeed] = []
        planted.reserveCapacity(count)

        for k in 0..<count {
            let species = theme.pickSpecies(using: &rng)
            // Births accelerate: a lonely first speck, then spores from the first colonies land everywhere.
            let f = Double(k) / Double(max(1, count - 1))
            let birth = duration * (0.035 + 0.62 * pow(f, 0.85)) + rng.double(in: -0.015...0.015) * duration

            let (x, y) = pickSpot(k: k, planted: planted, width: width, height: height, diag: diag, rng: &rng)

            let rate = diag * rng.double(in: species.growthPerMinute) / minute
            planted.append(ColonySeed(
                birth: max(duration * 0.02, birth),
                x: x, y: y,
                species: species,
                growthRate: rate,
                lag: rng.double(in: 1.5...4) * minute,
                maxRadius: diag * rng.double(in: 0.28...0.5),
                margin: rng.double(in: species.marginWidth),
                sporulationDelay: rng.double(in: 4...8) * minute,
                stretch: rng.double(in: 1.0...1.3),
                angle: rng.double(in: 0...Double.pi),
                noiseSeed: rng.double(in: 0...1)
            ))
        }
        // A spore landing on ground another colony already claimed never gets going.
        var viable: [ColonySeed] = []
        for candidate in planted.sorted(by: { $0.birth < $1.birth }) {
            let occupied = viable.contains { other in
                state(of: other, at: candidate.birth).map { $0.contains(candidate.x, candidate.y) } ?? false
            }
            if !occupied { viable.append(candidate) }
        }
        return viable
    }

    private static func pickSpot(
        k: Int, planted: [ColonySeed], width: Double, height: Double, diag: Double, rng: inout SeededRandom
    ) -> (Double, Double) {
        let roll = rng.double(in: 0...1)
        if k == 0 || roll < 0.3 {
            // Damp edges and corners, where it always starts (think: the bezel, the bottom of the fruit bowl).
            let band = 0.07
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: return (rng.double(in: 0...width), rng.double(in: 0...band) * height)
            case 1: return (rng.double(in: 0...width), height - rng.double(in: 0...band) * height)
            case 2: return (rng.double(in: 0...band) * width, rng.double(in: 0...height))
            default: return (width - rng.double(in: 0...band) * width, rng.double(in: 0...height))
            }
        }
        if roll < 0.55, let parent = planted.randomElement(using: &rng) {
            // Satellite colony: a spore that dropped close to its parent.
            let a = rng.double(in: 0...(2 * Double.pi))
            let d = diag * rng.double(in: 0.05...0.16)
            return (clamp(parent.x + cos(a) * d, 0, width), clamp(parent.y + sin(a) * d, 0, height))
        }
        // Best-candidate sampling: land somewhere not yet claimed, so the whole screen gets its turn.
        var best = (rng.double(in: 0...width), rng.double(in: 0...height))
        var bestDistance = -1.0
        for _ in 0..<8 {
            let c = (rng.double(in: 0...width), rng.double(in: 0...height))
            let nearest = planted.map { hypot($0.x - c.0, $0.y - c.1) }.min() ?? .infinity
            if nearest > bestDistance { bestDistance = nearest; best = c }
        }
        return best
    }
}

extension ColonyState {
    /// Point-in-ellipse test for the mycelium edge (no noise).
    public func contains(_ px: Double, _ py: Double) -> Bool {
        let dx = px - x, dy = py - y
        let c = cos(angle), s = sin(angle)
        let ex = (c * dx + s * dy) / stretch
        let ey = -s * dx + c * dy
        return ex * ex + ey * ey <= radius * radius
    }
}

@inline(__always) func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

@inline(__always) func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
}
