import Testing
@testable import MouldCore

struct MouldSimulationTests {
    static let screens: [(Double, Double)] = [(1512, 982), (1440, 900), (2560, 1440), (3440, 1440), (1080, 1920)]

    @Test func isDeterministicForASeed() {
        let a = MouldSimulation(width: 1512, height: 982, seed: 42, theme: .orange)
        let b = MouldSimulation(width: 1512, height: 982, seed: 42, theme: .orange)
        #expect(a.seeds == b.seeds)
        #expect(a.colonies(at: 1800) == b.colonies(at: 1800))
    }

    @Test func differentSeedsGrowDifferently() {
        let a = MouldSimulation(width: 1512, height: 982, seed: 1, theme: .orange)
        let b = MouldSimulation(width: 1512, height: 982, seed: 2, theme: .orange)
        #expect(a.seeds != b.seeds)
    }

    @Test func screenStartsClean() {
        let sim = MouldSimulation(width: 1512, height: 982, seed: 7, theme: .orange)
        #expect(sim.colonies(at: 0).isEmpty)
        #expect(sim.coverage(at: 0) == 0)
    }

    @Test func respectsColonyBudget() {
        let huge = MouldSimulation(width: 6016, height: 3384, seed: 3, theme: .compost)
        #expect(huge.seeds.count <= MouldSimulation.maxColonies)
        let tiny = MouldSimulation(width: 400, height: 300, seed: 3, theme: .compost)
        #expect(tiny.seeds.count == huge.seeds.count, "same story on every screen size")
    }

    @Test(arguments: screens)
    func growsSlowlyThenClaimsTheScreenWithinAnHour(size: (Double, Double)) {
        for seed in UInt64(1)...6 {
            let sim = MouldSimulation(width: size.0, height: size.1, seed: seed, theme: .compost)
            let at5 = sim.coverage(at: 5 * 60)
            let at15 = sim.coverage(at: 15 * 60)
            let at30 = sim.coverage(at: 30 * 60)
            let at60 = sim.coverage(at: 60 * 60)
            #expect(at5 < 0.02, "5 min should be a few specks, got \(at5)")
            #expect(at15 < 0.2, "15 min should still be subtle, got \(at15)")
            #expect((0.15...0.7).contains(at30), "30 min should be well under way, got \(at30)")
            #expect(at60 > 0.8, "an hour should claim most of the screen, got \(at60)")
        }
    }

    @Test func coverageNeverShrinks() {
        let sim = MouldSimulation(width: 1512, height: 982, seed: 11, theme: .strawberry)
        var last = 0.0
        for minute in stride(from: 0, through: 70, by: 2) {
            let c = sim.coverage(at: Double(minute) * 60, samplesAcross: 40)
            #expect(c >= last)
            last = c
        }
    }

    @Test func coloniesGrowMonotonicallyAndSporulateLater() {
        let sim = MouldSimulation(width: 1512, height: 982, seed: 5, theme: .orange)
        let seed = sim.seeds[0]
        var lastRadius = 0.0
        for s in stride(from: seed.birth, through: seed.birth + 3000, by: 30) {
            let r = MouldSimulation.radius(of: seed, at: s)
            #expect(r >= lastRadius)
            #expect(r <= seed.maxRadius)
            lastRadius = r
        }
        // Fresh colonies are pure white fluff; the coloured spore mass comes later and stays inside.
        let young = sim.colonies(at: seed.birth + seed.sporulationDelay * 0.4).first!
        #expect(young.sporeRadius == 0)
        let old = sim.colonies(at: seed.birth + seed.sporulationDelay * 3).first!
        #expect(old.sporeRadius > 0)
        #expect(old.sporeRadius < old.radius)
        #expect(old.maturity == 1)
    }

    @Test func themesOnlyGrowTheirOwnFungi() {
        let orange = MouldSimulation(width: 1512, height: 982, seed: 9, theme: .orange)
        #expect(orange.seeds.allSatisfy { [.penicilliumDigitatum, .penicilliumItalicum].contains($0.species) })
        let strawberry = MouldSimulation(width: 1512, height: 982, seed: 9, theme: .strawberry)
        #expect(strawberry.seeds.allSatisfy { [.botrytisCinerea, .rhizopusStolonifer].contains($0.species) })
    }

    @Test func shortDurationsScaleTheWholeStory() {
        // A one-minute demo should look like the hour, just faster.
        let demo = MouldSimulation(width: 1512, height: 982, seed: 4, theme: .orange, duration: 60)
        #expect(demo.coverage(at: 60) > 0.8)
        #expect(demo.coverage(at: 5) < 0.02)
    }

    @Test func coloniesLandOnScreen() {
        let sim = MouldSimulation(width: 1512, height: 982, seed: 21, theme: .compost)
        for s in sim.seeds {
            #expect((0...1512).contains(s.x))
            #expect((0...982).contains(s.y))
        }
    }
}

struct GrowthClockTests {
    @Test func accumulatesWhileActive() {
        var clock = GrowthClock()
        clock.advance(by: 1, idleFor: 0)
        clock.advance(by: 2, idleFor: 10)
        #expect(clock.elapsed == 3)
    }

    @Test func pausesWhileUserIsAway() {
        var clock = GrowthClock(idleThreshold: 300)
        clock.advance(by: 1, idleFor: 301)
        #expect(clock.elapsed == 0)
    }

    @Test func ignoresHugeJumpsAndNegativeTime() {
        var clock = GrowthClock(maxStep: 5)
        clock.advance(by: 3600, idleFor: 0)
        clock.advance(by: -10, idleFor: 0)
        #expect(clock.elapsed == 5)
    }

    @Test func speedMultiplies() {
        var clock = GrowthClock(speed: 60)
        clock.advance(by: 1, idleFor: 0)
        #expect(clock.elapsed == 60)
        #expect(clock.progress(duration: 3600) == 60.0 / 3600)
    }

    @Test func resetStartsOver() {
        var clock = GrowthClock()
        clock.advance(by: 4, idleFor: 0)
        clock.reset()
        #expect(clock.elapsed == 0)
        #expect(clock.progress(duration: 3600) == 0)
    }
}

struct WipeAnimationTests {
    @Test func easesFromZeroToOne() {
        var wipe = WipeAnimation(duration: 2)
        #expect(wipe.progress == 0)
        #expect(!wipe.isFinished)
        wipe.advance(by: 1)
        #expect(abs(wipe.progress - 0.5) < 1e-9)
        wipe.advance(by: 5)
        #expect(wipe.progress == 1)
        #expect(wipe.isFinished)
    }

    @Test func progressIsMonotonic() {
        var wipe = WipeAnimation(duration: 1)
        var last = -1.0
        for _ in 0..<20 {
            wipe.advance(by: 0.06)
            #expect(wipe.progress >= last)
            last = wipe.progress
        }
    }
}

struct KeyComboTests {
    @Test func displaysInAppleOrder() {
        #expect(KeyCombo.clearMould.displayString == "⌃⌥⌘M")
        let combo = KeyCombo(keyCode: 0, key: "a", modifiers: [.command, .shift, .option])
        #expect(combo.displayString == "⌥⇧⌘A")
    }

    @Test func modifierBitsMatchCarbon() {
        // cmdKey = 256, shiftKey = 512, optionKey = 2048, controlKey = 4096
        #expect(KeyCombo.Modifiers.command.rawValue == 256)
        #expect(KeyCombo.Modifiers.shift.rawValue == 512)
        #expect(KeyCombo.Modifiers.option.rawValue == 2048)
        #expect(KeyCombo.Modifiers.control.rawValue == 4096)
    }
}

struct ThemeTests {
    @Test func speciesPickingIsDistributed() {
        var rng = SeededRandom(seed: 99)
        var counts: [Species: Int] = [:]
        for _ in 0..<2000 { counts[Theme.orange.pickSpecies(using: &rng), default: 0] += 1 }
        let green = Double(counts[.penicilliumDigitatum] ?? 0) / 2000
        #expect((0.58...0.72).contains(green))
        #expect(counts[.botrytisCinerea] == nil)
    }
}

struct RedrawPolicyTests {
    @Test func realTimeIsGentleOnTheBattery() {
        #expect(RedrawPolicy.interval(speed: 1, wiping: false) == 2)
    }

    @Test func demosAndWipesAreSmooth() {
        #expect(RedrawPolicy.interval(speed: 60, wiping: false) == 1.0 / 30)
        #expect(RedrawPolicy.interval(speed: 5, wiping: false) == 0.4)
        #expect(RedrawPolicy.interval(speed: 1, wiping: true) == 1.0 / 60)
    }

    @Test func jumpSetsElapsed() {
        var clock = GrowthClock()
        clock.jump(to: 1200)
        #expect(clock.elapsed == 1200)
        clock.jump(to: -5)
        #expect(clock.elapsed == 0)
    }
}

struct ResetTriggerTests {
    @Test func everyTriggerIsObservable() {
        for trigger in ResetTrigger.allCases {
            #expect(trigger.distributedNotificationName != nil || trigger.workspaceNotificationName != nil)
        }
    }

    @Test func coversLockAndScreensaver() {
        let names = ResetTrigger.allCases.compactMap(\.distributedNotificationName)
        #expect(names.contains("com.apple.screenIsLocked"))
        #expect(names.contains("com.apple.screensaver.didstart"))
    }
}

struct MouldMoodTests {
    @Test func startsFreshAndEndsFurry() {
        #expect(MouldMood.headline(progress: 0) == "Fresh as a daisy")
        #expect(MouldMood.headline(progress: 1) == "Fully furry. Go outside.")
        #expect(MouldMood.headline(progress: 7) == "Fully furry. Go outside.")
        #expect(MouldMood.headline(progress: -1) == "Fresh as a daisy")
    }

    @Test func linesAreOrdered() {
        let bounds = MouldMood.lines.map(\.upTo)
        #expect(bounds == bounds.sorted())
        #expect(bounds.last == 1)
    }
}

struct DormancyTests {
    @Test func sporesDoNotGerminateOnClaimedGround() {
        for seed in UInt64(1)...10 {
            let sim = MouldSimulation(width: 1512, height: 982, seed: seed, theme: .compost)
            for (i, colony) in sim.seeds.enumerated() {
                for earlier in sim.seeds[..<i] {
                    let state = sim.colonies(at: colony.birth).first { $0.x == earlier.x && $0.y == earlier.y }
                    #expect(state?.contains(colony.x, colony.y) != true)
                }
            }
        }
    }
}

struct AngularProfileTests {
    @Test func isBoundedAndDeterministic() {
        let a = AngularProfile.make(seed: 0.42)
        #expect(a == AngularProfile.make(seed: 0.42))
        #expect(a != AngularProfile.make(seed: 0.43))
        #expect(a.count == AngularProfile.samples)
        for v in a {
            #expect((-0.5...0.5).contains(v.x) && (-0.5...0.5).contains(v.y) && (-0.5...0.5).contains(v.z))
            #expect((0...1).contains(v.w))
        }
    }

    @Test func wrapsSeamlesslyAroundTheCircle() {
        // The last sample must flow into the first like any two neighbours do, or colonies get a crack.
        let a = AngularProfile.make(seed: 0.7)
        func step(_ i: Int, _ j: Int) -> Float { abs(a[i].x - a[j].x) + abs(a[i].z - a[j].z) }
        let typical = (1..<a.count).map { step($0, $0 - 1) }.max()!
        #expect(step(0, a.count - 1) <= typical * 1.01)
    }
}
