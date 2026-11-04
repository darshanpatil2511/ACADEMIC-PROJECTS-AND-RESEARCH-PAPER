import CoreGraphics
import Testing
@testable import CurbCore

@Suite("Live pipeline")
struct LivePipelineTests {
    // MARK: Steadiness

    @Test func steadyOnlyWhenUprightAndStill() {
        #expect(SteadinessRule.isSteady(MotionSample(gravityY: -0.98, rotationRate: (0.05, 0.1, 0.0))))
        // Tilted flat (looking at the ground): not upright.
        #expect(!SteadinessRule.isSteady(MotionSample(gravityY: -0.3, rotationRate: (0, 0, 0))))
        // Upright but turning: 0.4^2 + 0.4^2 -> 0.57 rad/s.
        #expect(!SteadinessRule.isSteady(MotionSample(gravityY: -0.95, rotationRate: (0.4, 0.4, 0))))
    }

    // MARK: Voting

    private let twoHour = ParkingRule(kind: .timeLimit(minutes: 120), days: .everyDay,
                                      window: TimeWindow(start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 18)),
                                      season: nil, towZone: false, sourceText: "frame A")
    private var misread: ParkingRule {
        var r = twoHour
        r.kind = .timeLimit(minutes: 60)
        return r
    }

    @Test func becomesStableAfterThreeAgreeingFrames() {
        var voter = FrameVoter()
        #expect(voter.add([twoHour]).stableRules == nil)
        #expect(voter.add([misread]).stableRules == nil)
        #expect(voter.add([twoHour]).stableRules == nil)
        var copy = twoHour
        copy.sourceText = "frame D"      // different OCR text, same meaning: still a vote
        let result = voter.add([copy])
        #expect(result.topVotes == 3)
        #expect(result.stableRules == [twoHour.withoutSource])
    }

    @Test func emptyFramesNeverWin() {
        var voter = FrameVoter()
        for _ in 0..<6 { #expect(voter.add([]).stableRules == nil) }
    }

    @Test func oldVotesFallOutOfTheWindow() {
        var voter = FrameVoter(window: 6, threshold: 3)
        _ = voter.add([twoHour]); _ = voter.add([twoHour]); _ = voter.add([twoHour])
        #expect(voter.add([]).stableRules != nil)
        for _ in 0..<3 { _ = voter.add([misread]) }
        // Window now: [empty, misread, misread, misread] + last two twoHour pushed out.
        #expect(voter.add([misread]).stableRules == [misread.withoutSource])
    }

    // MARK: Throttle

    @Test func throttleLimitsRateAndConcurrency() {
        let throttle = FrameThrottle(maxPerSecond: 3)
        #expect(throttle.tryBegin(now: 0.0))
        #expect(!throttle.tryBegin(now: 0.5))       // still busy
        throttle.end()
        #expect(throttle.tryBegin(now: 0.5))        // 0.5 s later, free
        throttle.end()
        #expect(!throttle.tryBegin(now: 0.6))       // only 0.1 s since last start
        #expect(throttle.tryBegin(now: 0.84))
        throttle.end()
        throttle.setEnabled(false)
        #expect(!throttle.tryBegin(now: 5))         // not steady
    }

    // MARK: Preview mapping

    @Test func aspectFillCropsTheLongSide() {
        // 1080x1920 portrait frame shown in a 390x844 view: scale = max(390/1080, 844/1920) = 0.4396.
        let image = CGSize(width: 1080, height: 1920)
        let view = CGSize(width: 390, height: 844)
        let full = VisionGeometry.aspectFillRect(CGRect(x: 0, y: 0, width: 1, height: 1), imageSize: image, viewSize: view)
        #expect(abs(full.height - 844) < 0.01)
        #expect(abs(full.width - 474.75) < 0.01)    // wider than the view: sides are cropped
        #expect(abs(full.minX - (-42.375)) < 0.01)
        // Vision's top-right corner lands at the view's top-right (minus the cropped margin).
        let topRight = VisionGeometry.aspectFillPoint(CGPoint(x: 1, y: 1), imageSize: image, viewSize: view)
        #expect(abs(topRight.x - 432.375) < 0.01 && abs(topRight.y) < 0.01)
        // The center stays the center.
        let center = VisionGeometry.aspectFillPoint(CGPoint(x: 0.5, y: 0.5), imageSize: image, viewSize: view)
        #expect(abs(center.x - 195) < 0.01 && abs(center.y - 422) < 0.01)
    }
}
