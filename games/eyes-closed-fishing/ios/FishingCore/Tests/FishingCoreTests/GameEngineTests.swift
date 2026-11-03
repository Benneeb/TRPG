import XCTest
@testable import FishingCore

/// 시드 고정 엔진을 가짜 시계로 돌려 보는 헤드리스 플레이 테스트
final class GameEngineTests: XCTestCase {
    private final class Harness {
        let engine: GameEngine
        var t: Double = 0
        var events: [GameEvent] = []
        var pendingSpeech: [Int] = []
        var speechClock = 0.0

        init(seed: UInt64, tutorialDone: Bool = true, failHint: Bool = false) {
            var save = SaveData()
            save.tutorialDone = tutorialDone
            save.settings.failHint = failHint
            engine = GameEngine(save: save, seed: seed)
            engine.onEvent = { [unowned self] e in
                self.events.append(e)
                if case let .speak(id, _) = e { self.pendingSpeech.append(id) }
            }
        }

        /// 음성은 0.5초 뒤 끝난 것으로 처리
        func run(_ seconds: Double, step: Double = 1.0 / 60.0, each: (() -> Void)? = nil) {
            let end = t + seconds
            while t < end {
                t += step
                engine.advance(to: t)
                if !pendingSpeech.isEmpty {
                    speechClock += step
                    if speechClock >= 0.5 {
                        speechClock = 0
                        let id = pendingSpeech.removeFirst()
                        engine.speechFinished(id: id, at: t)
                    }
                }
                each?()
            }
        }

        func runUntil(_ cond: () -> Bool, limit: Double = 30) -> Bool {
            let end = t + limit
            while t < end {
                run(1.0 / 60.0)
                if cond() { return true }
            }
            return false
        }

        func tap() {
            engine.press(at: t)
            engine.release(at: t + 0.01)
            t += 0.01
        }
    }

    func testCastLeadsToBiteWithinSpeciesWaitRange() {
        let h = Harness(seed: 1)
        h.engine.start(at: 0)
        XCTAssertTrue(h.runUntil { h.engine.phase == .idle })
        h.tap()
        XCTAssertEqual(h.engine.phase, .casting)
        let castAt = h.t
        XCTAssertTrue(h.runUntil({ h.engine.phase == .bite }, limit: 20))
        let sp = h.engine.round!.species
        let elapsed = h.t - castAt - GameEngine.castDuration
        XCTAssertGreaterThanOrEqual(elapsed, sp.wait.lowerBound - 0.05)
        XCTAssertLessThanOrEqual(elapsed, sp.wait.upperBound + 0.05)
    }

    func testTappingDuringWaitIsEarlyFail() {
        let h = Harness(seed: 2)
        h.engine.start(at: 0)
        _ = h.runUntil { h.engine.phase == .idle }
        h.tap()
        XCTAssertTrue(h.runUntil { h.engine.phase == .waiting })
        h.run(0.3)
        h.tap()
        XCTAssertEqual(h.engine.phase, .failed(.early))
        XCTAssertTrue(h.runUntil { h.engine.phase == .idle })
    }

    func testIgnoringBiteIsLateFail() {
        let h = Harness(seed: 3)
        h.engine.start(at: 0)
        _ = h.runUntil { h.engine.phase == .idle }
        h.tap()
        XCTAssertTrue(h.runUntil { h.engine.phase == .bite })
        XCTAssertTrue(h.runUntil({ h.engine.phase == .failed(.late) }, limit: 2))
    }

    func testHoldingForeverSnapsLine() {
        let h = Harness(seed: 4)
        h.engine.start(at: 0)
        _ = h.runUntil { h.engine.phase == .idle }
        h.tap()
        XCTAssertTrue(h.runUntil { h.engine.phase == .bite })
        h.engine.press(at: h.t)
        XCTAssertTrue(h.runUntil({ h.engine.phase == .failed(.snap) }, limit: 15))
    }

    func testReleasingForeverLetsFishEscape() {
        let h = Harness(seed: 5)
        h.engine.start(at: 0)
        _ = h.runUntil { h.engine.phase == .idle }
        h.tap()
        XCTAssertTrue(h.runUntil { h.engine.phase == .bite })
        h.tap()
        XCTAssertEqual(h.engine.phase, .reeling)
        XCTAssertTrue(h.runUntil({ h.engine.phase == .failed(.escape) }, limit: 10))
    }

    func testSkilledPlayerCatchesFishAndRecordsIt() {
        for seed in UInt64(10)..<UInt64(20) {
            let h = Harness(seed: seed)
            h.engine.start(at: 0)
            _ = h.runUntil { h.engine.phase == .idle }
            h.tap()
            XCTAssertTrue(h.runUntil { h.engine.phase == .bite })
            h.run(0.15)
            h.engine.press(at: h.t)
            // 장력이 높아지면 떼고, 낮아지면 다시 누르는 플레이어
            let ok = h.runUntil({
                guard let r = h.engine.round else { return true }
                if h.engine.phase == .reeling {
                    if h.engine.isPressed && r.tension > 75 { h.engine.release(at: h.t) }
                    else if !h.engine.isPressed && r.tension < 45 { h.engine.press(at: h.t) }
                }
                return h.engine.phase != .reeling
            }, limit: 60)
            XCTAssertTrue(ok)
            XCTAssertEqual(h.engine.phase, .caught, "seed \(seed): \(h.engine.phase)")
            XCTAssertEqual(h.engine.save.stats.totalCatches, 1)
            XCTAssertTrue(h.events.contains { if case .caught = $0 { return true }; return false })
            let id = h.engine.round!.species.id
            XCTAssertEqual(h.engine.save.record(for: id).count, 1)
            XCTAssertTrue(h.engine.save.stats.perfectHooks == 1)
            h.engine.release(at: h.t)
            XCTAssertTrue(h.runUntil { h.engine.phase == .idle })
        }
    }

    func testTutorialCompletesAndIsSaved() {
        let h = Harness(seed: 7, tutorialDone: false)
        h.engine.start(at: 0)
        XCTAssertEqual(h.engine.phase, .intro)
        XCTAssertTrue(h.engine.tutorialActive)
        XCTAssertTrue(h.runUntil { h.engine.phase == .idle })
        h.tap()
        XCTAssertTrue(h.runUntil({ h.engine.phase == .bite }, limit: 20))
        XCTAssertEqual(h.engine.round?.species.id, .crucian)
        h.engine.press(at: h.t)
        XCTAssertEqual(h.engine.phase, .reeling)
        XCTAssertTrue(h.engine.round!.frozen)
        // 미리듣기 동안 마찰음 장력이 올라감
        XCTAssertTrue(h.runUntil { h.engine.strainTension > 60 })
        XCTAssertTrue(h.runUntil { h.engine.round.map { !$0.frozen } == true })
        let ok = h.runUntil({
            guard let r = h.engine.round, h.engine.phase == .reeling else { return true }
            if h.engine.isPressed && r.tension > 75 { h.engine.release(at: h.t) }
            else if !h.engine.isPressed && r.tension < 45 { h.engine.press(at: h.t) }
            return false
        }, limit: 60)
        XCTAssertTrue(ok)
        XCTAssertEqual(h.engine.phase, .caught)
        h.engine.release(at: h.t)
        XCTAssertTrue(h.runUntil { h.engine.phase == .idle })
        XCTAssertFalse(h.engine.tutorialActive)
        XCTAssertTrue(h.engine.save.tutorialDone)
    }

    func testAbortReturnsToIdleSilently() {
        let h = Harness(seed: 8)
        h.engine.start(at: 0)
        _ = h.runUntil { h.engine.phase == .idle }
        h.tap()
        _ = h.runUntil { h.engine.phase == .waiting }
        h.engine.abort(at: h.t)
        XCTAssertEqual(h.engine.phase, .idle)
        XCTAssertNil(h.engine.round)
        h.run(15)
        XCTAssertEqual(h.engine.phase, .idle)
    }

    func testSpeechDeadlineKeepsGameMovingWithoutTTS() {
        let h = Harness(seed: 9)
        h.engine.onEvent = nil // 음성 완료 신호가 오지 않는 기기
        h.engine.start(at: 0)
        var t = 0.0
        while t < 20 { t += 1.0 / 60.0; h.engine.advance(to: t) }
        XCTAssertEqual(h.engine.phase, .idle)
    }

    func testDoubleTapCastOption() {
        let h = Harness(seed: 11)
        h.engine.save.settings.doubleTapCast = true
        h.engine.start(at: 0)
        _ = h.runUntil { h.engine.phase == .idle }
        h.tap()
        XCTAssertEqual(h.engine.phase, .idle)
        h.run(0.1)
        h.tap()
        XCTAssertEqual(h.engine.phase, .casting)
    }

    func testRecordsSummaryWording() {
        var save = SaveData()
        save.stats.totalCatches = 41
        save.fish["catfish"] = FishRecord(count: 3, maxSize: 97)
        save.fish["crucian"] = FishRecord(count: 38, maxSize: 34)
        let e = GameEngine(save: save, seed: 1)
        XCTAssertEqual(e.recordsSummary(), "지금까지 41마리를 잡았습니다. 다섯 종 중 두 종을 발견했습니다. 최대 기록은 메기 97센티미터입니다.")
    }

    func testSaveDataDecodesMissingKeysWithDefaults() throws {
        let json = #"{"stats":{"totalCasts":3},"fish":{"carp":{"count":1,"maxSize":48}}}"#.data(using: .utf8)!
        let d = try JSONDecoder().decode(SaveData.self, from: json)
        XCTAssertEqual(d.stats.totalCasts, 3)
        XCTAssertEqual(d.settings, GameSettings())
        XCTAssertEqual(d.record(for: .carp).maxSize, 48)
        XCTAssertFalse(d.tutorialDone)
    }
}

final class SynthTests: XCTestCase {
    func testEverySoundRendersAudibleFiniteSamples() {
        for key in SoundKey.allCases {
            for v in 0..<key.variantCount {
                let b = SoundRecipes.render(key, variant: v)
                XCTAssertFalse(b.samples.contains { !$0.isFinite }, "\(key) has NaN")
                XCTAssertGreaterThan(b.peak, 0.005, "\(key) is silent")
                XCTAssertLessThanOrEqual(b.peak, 0.981, "\(key) clips")
            }
        }
    }

    func testRenderingIsDeterministic() {
        let a = SoundRecipes.render(.bite(.carp), variant: 1)
        let b = SoundRecipes.render(.bite(.carp), variant: 1)
        XCTAssertEqual(a.samples, b.samples)
    }
}
