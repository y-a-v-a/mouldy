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

/// Pointers as macOS 26 shows them, in points.
private enum Pointer {
    static let camera = ScreenshotDetection.windowPickerCursor
    /// ⌘⇧4's crosshair prints the pointer's coordinates beside it, so its width follows their digits.
    static func crosshair(width: Double = 64) -> CursorShape { CursorShape(width: width, height: 40, hotX: 15, hotY: 15) }
    static let arrow = CursorShape(width: 28, height: 40, hotX: 5, hotY: 5)
    static let iBeam = CursorShape(width: 23, height: 22, hotX: 11.5, hotY: 11)
    static let hand = CursorShape(width: 32, height: 32, hotX: 13, hotY: 8)
    static let resize = CursorShape(width: 24, height: 18, hotX: 12, hotY: 9)
}

struct ScreenshotDetectionTests {
    @Test func recognisesTheCameraAtAnyPointerSize() {
        #expect(Pointer.camera.isScaled(Pointer.camera))
        #expect(CursorShape(width: 56, height: 50, hotX: 28, hotY: 22).isScaled(Pointer.camera), "Accessibility's pointer size")
        #expect(CursorShape(width: 42, height: 38, hotX: 21, hotY: 16).isScaled(Pointer.camera), "rounded")
    }

    @Test func noOtherPointerLooksLikeIt() {
        let others = [
            Pointer.crosshair(), Pointer.crosshair(width: 72), CursorShape(width: 32, height: 32, hotX: 15, hotY: 15),
            Pointer.arrow, Pointer.iBeam, Pointer.hand, Pointer.resize,
            CursorShape(width: 28, height: 26, hotX: 12, hotY: 11), // zoom in
            CursorShape(width: 24, height: 24, hotX: 11, hotY: 11), // cross
            CursorShape(width: 30, height: 24, hotX: 15, hotY: 12), // resize left/right
            CursorShape(width: 0, height: 0, hotX: 0, hotY: 0),
        ]
        for cursor in others {
            #expect(!cursor.isScaled(Pointer.camera), "\(cursor)")
        }
    }
}

struct CrosshairTests {
    @Test func recognisesTheCrosshairWithItsCoordinates() {
        let crosshair = ScreenshotDetection.regionPickerCursor
        #expect(Pointer.crosshair().extends(crosshair))
        #expect(Pointer.crosshair(width: 72).extends(crosshair))
        #expect(CursorShape(width: 128, height: 80, hotX: 30, hotY: 30).extends(crosshair), "a larger pointer")
        for other in [Pointer.camera, Pointer.arrow, Pointer.iBeam, Pointer.hand, Pointer.resize] {
            #expect(!other.extends(crosshair), "\(other)")
        }
    }
}

struct ScreenshotGuardTests {
    // Poll-by-poll, the way MouldController feeds it.
    private struct Session {
        var guardian = ScreenshotGuard(afterCapture: 4)
        var time = 0.0
        var cursor: CursorShape? = Pointer.iBeam
        var mouse = false
        var lastKeyDown = -100.0

        mutating func tick(_ seconds: Double = 1.0 / 30) {
            time += seconds
            guardian.observe(cursor: cursor, mouseDown: mouse, lastKeyDown: lastKeyDown, at: time)
        }
        /// A key goes down (which one can't be seen) just before the next look.
        mutating func key() {
            lastKeyDown = time + 0.0005
            tick(0.001)
        }
        /// ⌘⇧4: the 4 goes down, and the crosshair shows a moment later.
        mutating func commandShift4() {
            key()
            tick(0.3)
            point(Pointer.crosshair())
        }
        mutating func point(_ cursor: CursorShape?, for seconds: Double = 1.0 / 30) {
            self.cursor = cursor
            tick(seconds)
        }
        var aside: Bool { guardian.shouldStepAside(at: time) }
        mutating func click() { mouse = true; tick(); mouse = false; tick() }
    }

    @Test func staysForTheCrosshairAndARegionCapture() {
        var s = Session()
        s.point(Pointer.crosshair(), for: 3)
        #expect(!s.aside, "a region capture keeps the mould")
        s.mouse = true; s.tick(); s.tick(0.5); s.mouse = false; s.tick()
        s.point(Pointer.arrow, for: 5)
        #expect(!s.aside, "and it stays while the thumbnail floats")
    }

    @Test func stepsAsideForWindowSelection() {
        var s = Session()
        s.point(Pointer.crosshair())
        s.point(Pointer.camera)
        #expect(s.aside, "Space: the picker must see through the mould")
        s.tick(20)
        #expect(s.aside, "however long the choice takes")
        s.point(Pointer.crosshair())
        #expect(!s.aside, "Space again: back to a region")
    }

    @Test func comesBackFourSecondsAfterTheWindowIsCaptured() {
        var s = Session()
        s.point(Pointer.crosshair())
        s.point(Pointer.camera)
        s.click()
        let captured = s.time
        s.point(Pointer.camera) // the camera can outlast the click by a poll or two
        s.point(Pointer.arrow)
        #expect(s.guardian.shouldStepAside(at: captured + 3.9))
        #expect(!s.guardian.shouldStepAside(at: captured + 4.1), "back while the thumbnail still floats")
    }

    @Test func escapeBringsTheMouldBack() {
        var s = Session()
        s.point(Pointer.crosshair())
        s.point(Pointer.arrow)
        #expect(!s.aside, "Esc from the crosshair")
        s.point(Pointer.crosshair())
        s.point(Pointer.camera)
        s.point(Pointer.arrow)
        #expect(!s.aside, "Esc from window selection: nothing was captured")
    }

    @Test func onlyAClickOnAWindowCounts() {
        var s = Session()
        s.click()
        #expect(!s.aside, "an ordinary click")
        s.point(Pointer.crosshair())
        s.click()
        s.point(Pointer.arrow)
        #expect(!s.aside, "a click in the crosshair")
    }

    @Test func aWanderingPointerLeavesTheMouldAlone() {
        var s = Session()
        // Around ⌘⇧3, ⌘⇧T, ⌘⇧[... and while a thumbnail floats: text, links, window edges.
        for cursor in [Pointer.arrow, Pointer.iBeam, Pointer.hand, Pointer.resize, Pointer.iBeam, nil] {
            s.point(cursor, for: 0.5)
            #expect(!s.aside, "\(cursor.map(String.init(describing:)) ?? "no pointer")")
        }
    }

    @Test func theCrosshairMayChangeSizeAsItMoves() {
        var s = Session()
        for width in [64.0, 72, 56, 64] {
            s.point(Pointer.crosshair(width: width), for: 0.5)
            #expect(!s.aside, "coordinates with other digits")
        }
    }

    @Test func noCrosshairNeededBeforeTheCamera() {
        var s = Session()
        s.point(Pointer.iBeam)
        s.point(Pointer.camera)
        #expect(s.aside, "⌘⇧4 and Space before the crosshair was ever seen")
    }

    @Test func aSecondWindowWhileTheThumbnailFloats() {
        var s = Session()
        s.point(Pointer.camera)
        s.click()
        s.point(Pointer.arrow, for: 5)
        #expect(!s.aside)
        s.point(Pointer.crosshair())
        s.point(Pointer.camera, for: 3)
        #expect(s.aside, "selecting the second window")
        s.click()
        s.point(Pointer.arrow, for: 3)
        #expect(s.aside, "and holding off after it")
    }

    @Test func watchesEveryMillisecondWhileSpaceMayCome() {
        var s = Session()
        #expect(s.guardian.pollInterval == ScreenshotDetection.pollInterval)
        s.point(Pointer.crosshair())
        #expect(s.guardian.pollInterval == ScreenshotDetection.crosshairPollInterval, "the picker settles within ~20 ms")
        s.point(Pointer.camera)
        #expect(s.guardian.pollInterval == ScreenshotDetection.pollInterval)
    }

    @Test func stepsAsideAsSpaceGoesDown() {
        var s = Session()
        s.commandShift4()
        s.tick(1)
        #expect(!s.aside, "⌘⇧4's own key doesn't count")
        s.key()
        #expect(s.aside, "Space: ahead of the camera, as the picker settles within milliseconds of it")
        s.point(Pointer.camera, for: 3)
        #expect(s.aside)
    }

    @Test func spaceAgainBringsTheMouldBack() {
        var s = Session()
        s.commandShift4()
        s.key()
        s.point(Pointer.camera, for: 2)
        s.key()
        #expect(s.aside, "the camera is still up")
        s.point(Pointer.crosshair(), for: 2)
        #expect(!s.aside, "back to a region")
        s.key()
        #expect(s.aside, "and on to a window once more")
    }

    @Test func escapeOnlyBlinks() {
        var s = Session()
        s.commandShift4()
        s.key()
        #expect(s.aside, "Esc can't be told apart from Space")
        s.point(Pointer.arrow)
        #expect(!s.aside, "until the crosshair goes")
    }

    @Test func spaceWhileDraggingMovesTheRegion() {
        var s = Session()
        s.commandShift4()
        s.mouse = true
        s.tick()
        s.key()
        s.tick(0.5)
        s.mouse = false
        s.tick()
        #expect(!s.aside, "the region is captured with the mould")
    }

    @Test func typingElsewhereDoesNothing() {
        var s = Session()
        for _ in 0..<5 {
            s.key()
            s.tick(0.2)
            #expect(!s.aside)
        }
    }

    @Test func largerPointersToo() {
        var s = Session()
        s.point(CursorShape(width: 56, height: 50, hotX: 28, hotY: 22))
        #expect(s.aside)
    }
}
