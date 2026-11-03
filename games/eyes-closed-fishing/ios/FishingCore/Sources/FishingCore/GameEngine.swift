import Foundation

// MARK: - 공개 타입

public enum FailReason: String, Codable, Sendable {
    case early   // 결정적 입질 전에 터치
    case late    // 챔질 판정창을 놓침
    case snap    // 장력 한계 → 줄 끊김
    case escape  // 줄이 너무 오래 느슨함 → 바늘 빠짐
}

public enum Phase: Equatable, Sendable {
    case boot
    case intro
    case idle
    case casting
    case waiting
    case bite
    case reeling
    case caught
    case failed(FailReason)

    public var isRoundActive: Bool {
        switch self {
        case .casting, .waiting, .bite, .reeling: return true
        default: return false
        }
    }
}

public enum SoundCue: Equatable, Sendable {
    case cast
    case approach
    case nibble
    case frog
    case leaf
    case goldTick
    case bite(SpeciesID)
    case hookSet(perfect: Bool)
    case run
    case thrash(volume: Float)
    case snap
    case hookFree
    case fleeEarly
    case missLate
    case catchSplash
    case record
    case ready
}

public enum HapticCue: Equatable, Sendable {
    case bite, hookSet, run, snap, caught
}

public struct CatchResult: Equatable, Sendable {
    public let species: SpeciesID
    public let size: Int
    public let isNew: Bool
    public let isRecord: Bool
    public let perfect: Bool
}

public enum GameEvent: Equatable, Sendable {
    case phaseChanged(Phase)
    case sound(SoundCue, pan: Float)
    case haptic(HapticCue)
    /// 음성 안내 요청. 재생이 끝나면 `speechFinished(id:at:)`를 호출해야 다음 단계로 진행합니다.
    case speak(id: Int, text: String)
    case stopSpeech
    case saveDataChanged
    case caught(CatchResult)
}

/// 한 마리를 낚는 동안의 상태
public struct Round: Equatable, Sendable {
    public let species: Species
    public var pan: Float
    public var tension: Double = 30
    public var distance: Double = 100
    public var slack: Double = 0
    public var runLeft: Double = 0
    public var nextRun: Double = .infinity
    public var thrashIn: Double = 1.5
    public var frozen = false
    public var biteAt: Double = 0
    public var size = 0
    public var perfect = false
}

// MARK: - 엔진

/// 화면·오디오와 분리된 순수 게임 규칙.
/// 호스트는 매 프레임 `advance(to:)`를 호출하고, 입력은 `press(at:)` / `release(at:)`로 전달합니다.
/// 모든 시간은 호스트가 주는 단조 증가 시계(초)를 기준으로 합니다.
public final class GameEngine {
    // 튜닝 상수
    public static let castDuration = 1.45
    public static let perfectHookWindow = 0.4
    public static let snapTension = 100.0
    public static let slackTension = 10.0
    public static let slackLimit = 3.0
    public static let tutorialHookWindow = 2.0
    public static let tutorialWait = 4.0
    public static let tutorialTensionScale = 0.5
    public static let doubleTapInterval = 0.4

    public private(set) var phase: Phase = .boot
    public private(set) var round: Round?
    public private(set) var tutorialActive = false
    public private(set) var now: Double = 0
    public var save: SaveData
    public var onEvent: ((GameEvent) -> Void)?

    private let rng: RNG
    private var pressed = false
    private var tutorialHinted = false
    private var lastIdleTap: Double = -10
    private var lastCatch: CatchResult?
    private var strainPreview: (start: Double, duration: Double)?

    // 현재 단계에 묶인 예약 동작 (단계가 바뀌면 모두 취소)
    private enum Scheduled {
        case cue(SoundCue, pan: Float)
        case castLanded
        case bite
        case biteTimeout
    }
    private var scheduled: [(at: Double, action: Scheduled)] = []

    // 음성·대기·동작을 순서대로 실행하는 짧은 스크립트 (튜토리얼, 결과 안내 등)
    private enum ScriptAction {
        case toIdle
        case enterIdleFromIntro
        case startWaiting(forced: Double?)
        case unfreezeReel
        case finishTutorial
        case beginStrainPreview(Double)
    }
    private enum ScriptStep {
        case say(String)
        case pause(Double)
        case run(ScriptAction)
    }
    private enum ScriptWait {
        case speech(id: Int, deadline: Double)
        case time(until: Double)
    }
    private var script: [ScriptStep] = []
    private var scriptWait: ScriptWait?
    private var inScriptLoop = false
    private var speechCounter = 0

    public init(save: SaveData = SaveData(), seed: UInt64? = nil) {
        self.save = save
        self.rng = seed.map { RNG(seed: $0) } ?? RNG()
    }

    // MARK: 오디오·햅틱이 매 프레임 읽는 값

    /// 줄 마찰음에 쓸 장력 (튜토리얼 미리듣기 포함)
    public var strainTension: Double {
        if let p = strainPreview {
            let x = (now - p.start) / p.duration
            if x >= 0, x <= 1 { return 50 + 48 * x }
        }
        if phase == .reeling, let r = round, !r.frozen { return r.tension }
        return 0
    }

    /// 릴을 실제로 감고 있는지
    public var isReeling: Bool {
        phase == .reeling && pressed && round.map { !$0.frozen } == true
    }

    /// 줄이 느슨해 경고음을 낼 상태인지
    public var isSlack: Bool {
        guard phase == .reeling, let r = round, !r.frozen else { return false }
        return r.tension < 15
    }

    public var isPressed: Bool { pressed }

    // MARK: 호스트 입력

    /// 시작 버튼을 누른 직후 호출
    public func start(at t: Double) {
        sync(t)
        if !save.tutorialDone {
            startTutorial(at: t)
        } else {
            setPhase(.idle)
            emit(.sound(.ready, pan: 0))
            runScript([.say("터치해서 낚싯줄을 던지세요.")])
        }
    }

    public func press(at t: Double) {
        advance(to: t)
        pressed = true
        switch phase {
        case .idle:
            if save.settings.doubleTapCast && !tutorialActive {
                if now - lastIdleTap < Self.doubleTapInterval {
                    lastIdleTap = -10
                    cast()
                } else {
                    lastIdleTap = now
                }
            } else {
                cast()
            }
        case .waiting:
            fail(.early)
        case .bite:
            hook()
        case .caught, .failed:
            if !tutorialActive {
                cancelScript()
                toIdle()
            }
        default:
            break
        }
    }

    public func release(at t: Double) {
        advance(to: t)
        pressed = false
    }

    public func speechFinished(id: Int, at t: Double) {
        advance(to: t)
        if case let .speech(current, _) = scriptWait, current == id {
            scriptWait = nil
            advanceScript()
        }
    }

    /// 앱이 백그라운드로 가거나 메뉴를 열 때: 진행 중인 판을 조용히 취소
    public func abort(at t: Double) {
        sync(t)
        cancelScript()
        scheduled.removeAll()
        strainPreview = nil
        pressed = false
        round = nil
        if phase != .boot { setPhase(.idle) }
    }

    /// 메뉴를 닫은 뒤 이어하기
    public func resume(at t: Double) {
        sync(t)
        if tutorialActive {
            startTutorial(at: t)
        } else {
            toIdle()
        }
    }

    public func startTutorial(at t: Double) {
        sync(t)
        cancelScript()
        scheduled.removeAll()
        round = nil
        tutorialActive = true
        tutorialHinted = false
        setPhase(.intro)
        runScript([
            .say("이어폰을 끼고 눈을 감아 보세요. 화면 아무 곳이나 한 번 터치하면 낚싯줄을 던집니다."),
            .run(.enterIdleFromIntro),
        ])
    }

    /// 기록 요약을 음성으로 읽기 (기획서 7.3)
    public func speakRecords(at t: Double) {
        sync(t)
        runScript([.say(recordsSummary())])
    }

    public func recordsSummary() -> String {
        let st = save.stats
        guard st.totalCatches > 0 else { return "아직 잡은 물고기가 없습니다." }
        let words = ["영", "한", "두", "세", "네", "다섯"]
        let found = save.discoveredCount
        var best: (name: String, size: Int)?
        for sp in Species.all {
            let rec = save.record(for: sp.id)
            if rec.count > 0, rec.maxSize > (best?.size ?? 0) { best = (sp.name, rec.maxSize) }
        }
        var text = "지금까지 \(st.totalCatches)마리를 잡았습니다. 다섯 종 중 \(words[min(found, 5)]) 종을 발견했습니다."
        if let best { text += " 최대 기록은 \(best.name) \(best.size)센티미터입니다." }
        return text
    }

    /// 시간을 진행합니다. 매 프레임 호출하세요.
    public func advance(to t: Double) {
        guard t > now else { return }
        // 큰 시간 간격(앱 일시정지 등)은 잘라서 물리 폭주를 막음
        if t - now > 0.5 { now = t - 0.5 }
        while now < t {
            let dt = min(1.0 / 120.0, t - now)
            now += dt
            step(dt)
        }
    }

    // MARK: 내부 진행

    private func sync(_ t: Double) {
        if t > now { advance(to: t) }
    }

    private func step(_ dt: Double) {
        // 예약 동작
        while let idx = scheduled.indices.min(by: { scheduled[$0].at < scheduled[$1].at }),
              scheduled[idx].at <= now {
            let item = scheduled.remove(at: idx)
            perform(item.action)
        }
        // 스크립트 대기
        if let wait = scriptWait {
            switch wait {
            case let .speech(_, deadline) where now >= deadline:
                scriptWait = nil
                advanceScript()
            case let .time(until) where now >= until:
                scriptWait = nil
                advanceScript()
            default:
                break
            }
        }
        if let p = strainPreview, now > p.start + p.duration { strainPreview = nil }
        if phase == .reeling { stepReel(dt) }
    }

    private func perform(_ action: Scheduled) {
        switch action {
        case let .cue(cue, pan):
            if phase == .waiting || phase == .caught { emit(.sound(cue, pan: pan)) }
        case .castLanded:
            castLanded()
        case .bite:
            bite()
        case .biteTimeout:
            if phase == .bite { fail(.late) }
        }
    }

    private func schedule(after delay: Double, _ action: Scheduled) {
        scheduled.append((now + delay, action))
    }

    private func setPhase(_ p: Phase) {
        phase = p
        scheduled.removeAll()
        emit(.phaseChanged(p))
    }

    private func emit(_ e: GameEvent) {
        onEvent?(e)
    }

    // MARK: 스크립트

    private func runScript(_ steps: [ScriptStep]) {
        cancelScript()
        script = steps
        if !inScriptLoop { advanceScript() }
    }

    private func cancelScript() {
        if case .speech = scriptWait { emit(.stopSpeech) }
        script.removeAll()
        scriptWait = nil
    }

    private func advanceScript() {
        guard !inScriptLoop else { return }
        inScriptLoop = true
        defer { inScriptLoop = false }
        while scriptWait == nil, !script.isEmpty {
            let stepItem = script.removeFirst()
            switch stepItem {
            case let .say(text):
                speechCounter += 1
                // 음성 엔진이 끝 신호를 주지 않아도 멈추지 않도록 안전 시한
                let estimate = max(1.6, Double(text.count) * 0.16 + 0.7)
                scriptWait = .speech(id: speechCounter, deadline: now + estimate + 4)
                emit(.speak(id: speechCounter, text: text))
            case let .pause(d):
                scriptWait = .time(until: now + d)
            case let .run(action):
                performScript(action)
            }
        }
    }

    private func performScript(_ action: ScriptAction) {
        switch action {
        case .toIdle:
            toIdle()
        case .enterIdleFromIntro:
            if phase == .intro { toIdle() }
        case let .startWaiting(forced):
            startWaiting(forced: forced)
        case .unfreezeReel:
            if phase == .reeling, round != nil {
                round!.frozen = false
                round!.tension = 25
            }
        case .finishTutorial:
            tutorialActive = false
            save.tutorialDone = true
            emit(.saveDataChanged)
            runScript([.say("이제 혼자서 낚시해 보세요. 터치하면 던집니다."), .run(.toIdle)])
        case let .beginStrainPreview(d):
            strainPreview = (now + 0.1, d)
        }
    }

    // MARK: 게임 흐름

    private func pickSpecies() -> Species {
        if tutorialActive { return Species.named(.crucian) }
        let total = Species.all.reduce(0) { $0 + $1.weight }
        var r = rng.unit() * total
        for sp in Species.all {
            r -= sp.weight
            if r < 0 { return sp }
        }
        return Species.all[0]
    }

    private func rollSize(_ sp: Species, perfect: Bool) -> Int {
        let lo = Double(sp.size.lowerBound), hi = Double(sp.size.upperBound)
        let span = hi - lo
        let mean = lo + span * (perfect ? 0.5 : 0.4)
        let v = mean + rng.gaussian() * span / 5
        return Int(min(hi, max(lo, v)).rounded())
    }

    private func cast() {
        cancelScript()
        let sp = pickSpecies()
        round = Round(species: sp, pan: Float(rng.range(-0.5, 0.5)))
        save.stats.totalCasts += 1
        emit(.saveDataChanged)
        setPhase(.casting)
        emit(.sound(.cast, pan: 0))
        schedule(after: Self.castDuration, .castLanded)
    }

    private func castLanded() {
        guard phase == .casting else { return }
        if tutorialActive && !tutorialHinted {
            tutorialHinted = true
            runScript([
                .say("작은 소리는 아직이에요. 크게 물이 튀는 소리가 나면 바로 터치하세요."),
                .run(.startWaiting(forced: Self.tutorialWait)),
            ])
        } else {
            startWaiting(forced: tutorialActive ? Self.tutorialWait : nil)
        }
    }

    private func startWaiting(forced: Double?) {
        guard phase == .casting, let r = round else { return }
        setPhase(.waiting)
        let sp = r.species
        let wait = forced ?? rng.range(sp.wait)
        let silence = sp.silence.map { rng.range($0) } ?? 0
        let windowEnd = max(1.2, wait - silence - 0.35)
        let pan = r.pan

        if sp.isGold {
            // 황금 잉어: 접근 후 일정한 3박 리듬
            let start = max(0.9, windowEnd - 1.0)
            schedule(after: rng.range(0.6, max(0.7, start - 0.8)), .cue(.approach, pan: pan))
            for dt in [0.0, 0.42, 0.84] {
                schedule(after: start + dt, .cue(.goldTick, pan: pan))
            }
        } else {
            let count = tutorialActive ? 2 : rng.int(sp.preSignals)
            let times = (0..<count).map { _ in rng.range(0.8, windowEnd) }.sorted()
            for (i, t) in times.enumerated() {
                schedule(after: t, .cue(i == 0 ? .approach : .nibble, pan: pan))
            }
        }
        // 가짜 신호 (기획서 7장: 청각적 집중 유도)
        if !tutorialActive && rng.chance(0.55) {
            for _ in 0..<rng.int(1...2) {
                let p = Float(rng.range(-0.95, 0.95))
                let t = rng.range(0.8, max(0.9, wait - 0.7))
                schedule(after: t, .cue(rng.chance(0.5) ? .frog : .leaf, pan: p))
            }
        }
        schedule(after: wait, .bite)
    }

    private func bite() {
        guard phase == .waiting, round != nil else { return }
        setPhase(.bite)
        round!.biteAt = now
        emit(.sound(.bite(round!.species.id), pan: round!.pan * 0.6))
        emit(.haptic(.bite))
        let window = tutorialActive ? Self.tutorialHookWindow : round!.species.hookWindow
        schedule(after: window, .biteTimeout)
    }

    private func hook() {
        guard var r = round else { return }
        let sp = r.species
        let reaction = now - r.biteAt
        r.perfect = reaction <= Self.perfectHookWindow
        r.size = rollSize(sp, perfect: r.perfect)
        r.distance = r.perfect ? 90 : 100
        r.tension = 30
        r.slack = 0
        r.runLeft = 0
        r.nextRun = sp.runGap.map { rng.range($0) } ?? .infinity
        r.thrashIn = rng.range(1, 2)
        r.frozen = tutorialActive
        round = r
        if r.perfect {
            save.stats.perfectHooks += 1
            emit(.saveDataChanged)
        }
        setPhase(.reeling)
        emit(.sound(.hookSet(perfect: r.perfect), pan: 0))
        emit(.haptic(.hookSet))
        if tutorialActive {
            runScript([
                .say("잘했어요. 손가락을 누르고 있으면 릴을 감습니다."),
                .say("이런 날카로운 소리가 나면 바로 손을 떼세요."),
                .run(.beginStrainPreview(2.4)),
                .pause(2.8),
                .say("이제 눌러서 감아 보세요."),
                .run(.unfreezeReel),
            ])
        }
    }

    private func stepReel(_ dt: Double) {
        guard var r = round, !r.frozen else { return }
        let sp = r.species
        let scale = tutorialActive ? Self.tutorialTensionScale : 1

        if r.runLeft > 0 {
            r.runLeft -= dt
        } else if let gap = sp.runGap {
            r.nextRun -= dt
            if r.nextRun <= 0 {
                r.runLeft = rng.range(sp.runDuration)
                r.nextRun = rng.range(gap) + r.runLeft
                r.pan = Float(min(0.9, max(-0.9, Double(r.pan) + rng.range(-0.6, 0.6))))
                emit(.sound(.run, pan: r.pan))
                emit(.haptic(.run))
            }
        }
        let inRun = r.runLeft > 0
        if pressed {
            r.tension += sp.rise * scale * dt
            r.distance -= sp.reel * dt
        } else {
            r.tension -= sp.fall * dt
            r.distance += sp.resist * dt
        }
        if inRun {
            r.tension += sp.runPush * scale * dt
            r.distance += sp.runPull * dt
        }
        r.tension = min(110, max(0, r.tension))
        r.distance = min(100, r.distance)

        // 남은 거리 신호: 가까울수록 물튀김이 커짐
        r.thrashIn -= dt
        if r.thrashIn <= 0 {
            r.thrashIn = rng.range(1.1, 2.4)
            r.pan = Float(min(0.8, max(-0.8, Double(r.pan) + rng.range(-0.25, 0.25))))
            if !inRun {
                let v = Float(0.05 + 0.33 * (1 - max(0, r.distance) / 100))
                emit(.sound(.thrash(volume: v), pan: r.pan))
            }
        }
        round = r

        if r.tension >= Self.snapTension { fail(.snap); return }
        if r.tension <= Self.slackTension {
            round!.slack += dt
            if round!.slack >= Self.slackLimit { fail(.escape); return }
        } else {
            round!.slack = 0
        }
        if r.distance <= 0 { caught() }
    }

    private func caught() {
        guard let r = round else { return }
        let sp = r.species
        var rec = save.record(for: sp.id)
        let isNew = rec.count == 0
        let isRecord = !isNew && r.size > rec.maxSize
        rec.count += 1
        rec.maxSize = max(rec.maxSize, r.size)
        save.fish[sp.id.rawValue] = rec
        save.stats.totalCatches += 1
        let result = CatchResult(species: sp.id, size: r.size, isNew: isNew, isRecord: isRecord, perfect: r.perfect)
        lastCatch = result

        setPhase(.caught)
        emit(.saveDataChanged)
        emit(.caught(result))
        emit(.sound(.catchSplash, pan: 0))
        emit(.haptic(.caught))

        var text = "\(sp.name), \(r.size)센티미터."
        if tutorialActive {
            text += " 첫 물고기입니다."
        } else if isNew {
            text += " 새로운 물고기입니다."
        } else if isRecord {
            text += " 신기록입니다."
            schedule(after: 0.9, .cue(.record, pan: 0))
        }
        runScript([.pause(1.3), .say(text), .run(tutorialActive ? .finishTutorial : .toIdle)])
    }

    private func fail(_ reason: FailReason) {
        let pan = round?.pan ?? 0
        setPhase(.failed(reason))
        let cue: SoundCue
        switch reason {
        case .early: cue = .fleeEarly
        case .late: cue = .missLate
        case .snap: cue = .snap
        case .escape: cue = .hookFree
        }
        emit(.sound(cue, pan: pan))
        if reason == .snap { emit(.haptic(.snap)) }

        if tutorialActive {
            let tip: String
            switch reason {
            case .early: tip = "조금 빨랐어요. 크게 물이 튀는 소리를 기다리세요. 다시 던져 보세요."
            case .late: tip = "조금 늦었어요. 크게 물이 튀면 바로 터치하세요. 다시 던져 보세요."
            case .snap: tip = "줄이 끊어졌어요. 날카로운 소리가 나면 손을 떼세요. 다시 던져 보세요."
            case .escape: tip = "줄이 너무 느슨했어요. 소리가 잦아들면 다시 누르세요. 다시 던져 보세요."
            }
            runScript([.pause(0.9), .say(tip), .run(.toIdle)])
        } else if save.settings.failHint {
            let text: String
            switch reason {
            case .early: text = "너무 빨랐어요."
            case .late: text = "놓쳤어요."
            case .snap: text = "줄이 끊어졌어요."
            case .escape: text = "물고기가 빠져나갔어요."
            }
            runScript([.pause(0.9), .say(text), .run(.toIdle)])
        } else {
            runScript([.pause(1.5), .run(.toIdle)])
        }
    }

    private func toIdle() {
        setPhase(.idle)
        emit(.sound(.ready, pan: 0))
    }
}
