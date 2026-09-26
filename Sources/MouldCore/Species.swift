/// The fungi we grow. Raw values are shared with the Metal shader, so keep them stable.
public enum Species: UInt32, CaseIterable, Sendable {
    /// Green mould of citrus: olive-green powdery spore mass ringed by a wide band of white mycelium.
    case penicilliumDigitatum = 0
    /// Blue mould of citrus: blue-green spores with a narrow white margin.
    case penicilliumItalicum = 1
    /// Grey mould of strawberries: dense grey-brown velvet with little conidia tufts.
    case botrytisCinerea = 2
    /// Whisker/pin mould of soft fruit: loose cottony white hyphae dotted with black sporangia.
    case rhizopusStolonifer = 3

    public var displayName: String {
        switch self {
        case .penicilliumDigitatum: "Penicillium digitatum (green mould)"
        case .penicilliumItalicum: "Penicillium italicum (blue mould)"
        case .botrytisCinerea: "Botrytis cinerea (grey mould)"
        case .rhizopusStolonifer: "Rhizopus stolonifer (pin mould)"
        }
    }

    /// Width of the white mycelium margin in points once the spore mass has formed.
    var marginWidth: ClosedRange<Double> {
        switch self {
        case .penicilliumDigitatum: 16...30
        case .penicilliumItalicum: 6...12
        case .botrytisCinerea: 8...16
        case .rhizopusStolonifer: 4...10
        }
    }

    /// Radial growth speed relative to the screen diagonal, per minute.
    var growthPerMinute: ClosedRange<Double> {
        switch self {
        case .penicilliumDigitatum: 0.0036...0.0056
        case .penicilliumItalicum: 0.0028...0.0046
        case .botrytisCinerea: 0.0034...0.0054
        case .rhizopusStolonifer: 0.0042...0.0066 // Rhizopus is notoriously fast
        }
    }
}

/// Which fruit the mould pretends to be growing on.
public enum Theme: UInt32, CaseIterable, Sendable {
    case orange = 0
    case strawberry = 1
    case compost = 2

    public var displayName: String {
        switch self {
        case .orange: "Forgotten orange"
        case .strawberry: "Punnet of strawberries"
        case .compost: "Compost bin (everything)"
        }
    }

    /// Relative likelihood of each species appearing.
    public var speciesWeights: [(Species, Double)] {
        switch self {
        case .orange: [(.penicilliumDigitatum, 0.65), (.penicilliumItalicum, 0.35)]
        case .strawberry: [(.botrytisCinerea, 0.7), (.rhizopusStolonifer, 0.3)]
        case .compost: Species.allCases.map { ($0, 0.25) }
        }
    }

    public func pickSpecies(using rng: inout SeededRandom) -> Species {
        let weights = speciesWeights
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = rng.double(in: 0...total)
        for (species, weight) in weights {
            if roll <= weight { return species }
            roll -= weight
        }
        return weights[weights.count - 1].0
    }
}
