import AVFoundation
import FishingCore
import SwiftUI
import UIKit

/// 게임 엔진(규칙)과 오디오·진동·음성·저장·화면을 잇는 중앙 컨트롤러.
@MainActor
final class GameController: ObservableObject {
    @Published private(set) var phase: Phase = .boot
    @Published private(set) var started = false
    @Published private(set) var audioReady = false
    @Published private(set) var save: SaveData
    @Published private(set) var caption = ""
    @Published private(set) var captionVisible = false
    @Published private(set) var assistTension: Double = 0
    @Published private(set) var assistDistance: Double = 0
    @Published var showingMenu = false

    private let engine: GameEngine
    private let audio = AudioEngine()
    private let speech = SpeechService()
    private let haptics = HapticsService()
    private let store = SaveStore()
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var currentSpeechID = 0
    private var captionHideTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var pendingTutorial = false

    init() {
        let loaded = store.load()
        save = loaded
        engine = GameEngine(save: loaded)
        engine.onEvent = { [weak self] event in self?.handle(event) }
        speech.onFinish = { [weak self] id in self?.speechDidFinish(id) }
        applySettings()
        observeSystem()
    }

    private var clock: Double { CACurrentMediaTime() }

    // MARK: 수명 주기

    func prepare() async {
        await audio.prepareBank()
        audioReady = true
    }

    func startGame() {
        guard audioReady, !started else { return }
        audio.start()
        haptics.start()
        started = true
        UIApplication.shared.isIdleTimerDisabled = true
        startDisplayLink()
        engine.start(at: clock)
    }

    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        guard started else { return }
        switch scenePhase {
        case .background:
            engine.abort(at: clock)
            speech.stop()
            hideCaption(after: 0)
            haptics.stop()
            audio.pause()
            displayLink?.isPaused = true
            UIApplication.shared.isIdleTimerDisabled = false
        case .active:
            audio.resume()
            haptics.start()
            lastFrame = clock
            displayLink?.isPaused = false
            UIApplication.shared.isIdleTimerDisabled = true
            if phase == .idle && !showingMenu { audio.play(.ready, pan: 0) }
        default:
            break
        }
    }

    // MARK: 입력

    func press() {
        guard started, !showingMenu else { return }
        engine.press(at: clock)
    }

    func release() {
        guard started else { return }
        engine.release(at: clock)
    }

    // MARK: 메뉴 (기록·설정)

    func openMenu() {
        guard started, !showingMenu else { return }
        engine.abort(at: clock)
        speech.stop()
        hideCaption(after: 0)
        audio.silenceContinuous()
        haptics.updateTension(0, active: false)
        showingMenu = true
    }

    /// 시트가 닫힐 때 호출 (버튼·스와이프 모두)
    func menuDidClose() {
        guard started else { return }
        speech.stop()
        if pendingTutorial {
            pendingTutorial = false
            engine.startTutorial(at: clock)
        } else {
            engine.resume(at: clock)
        }
    }

    func speakRecords() {
        engine.speakRecords(at: clock)
    }

    func replayTutorial() {
        // 시트가 닫힌 뒤 menuDidClose에서 시작
        pendingTutorial = true
        showingMenu = false
    }

    func resetRecords() {
        engine.save.resetRecords()
        persist()
    }

    func binding<T>(_ keyPath: WritableKeyPath<GameSettings, T>) -> Binding<T> {
        Binding(
            get: { self.save.settings[keyPath: keyPath] },
            set: { value in
                self.engine.save.settings[keyPath: keyPath] = value
                self.applySettings()
                self.persist()
            }
        )
    }

    func previewVoiceVolume() {
        currentSpeechID = -1
        speech.speak(id: -1, text: "음성 안내 크기입니다.")
    }

    // MARK: 엔진 이벤트

    private func handle(_ event: GameEvent) {
        switch event {
        case let .phaseChanged(p):
            phase = p
        case let .sound(cue, pan):
            audio.play(cue, pan: pan)
        case let .haptic(cue):
            haptics.play(cue)
        case let .speak(id, text):
            currentSpeechID = id
            showCaption(text)
            speech.speak(id: id, text: text)
        case .stopSpeech:
            speech.stop()
            hideCaption(after: 0)
        case .saveDataChanged:
            persist()
        case .caught:
            break
        }
    }

    private func speechDidFinish(_ id: Int) {
        if id == currentSpeechID { hideCaption(after: 0.6) }
        guard id >= 0 else { return }
        engine.speechFinished(id: id, at: clock)
    }

    private func showCaption(_ text: String) {
        captionHideTask?.cancel()
        caption = text
        captionVisible = save.settings.captions
        // VoiceOver 사용자는 TTS와 겹치지 않도록 자막을 따로 읽히지 않음 (화면은 accessibilityHidden)
    }

    private func hideCaption(after delay: Double) {
        captionHideTask?.cancel()
        captionHideTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            guard !Task.isCancelled else { return }
            self?.captionVisible = false
        }
    }

    private func persist() {
        save = engine.save
        store.save(engine.save)
    }

    private func applySettings() {
        let s = engine.save.settings
        audio.bgmVolume = s.bgmVolume
        audio.sfxVolume = s.sfxVolume
        speech.volume = s.voiceVolume
        haptics.enabled = s.haptics
        if !s.captions { captionVisible = false }
    }

    // MARK: 프레임 루프

    private func startDisplayLink() {
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = clock
    }

    fileprivate func frame() {
        let t = clock
        let dt = min(0.05, max(0, t - lastFrame))
        lastFrame = t
        engine.advance(to: t)
        audio.update(reeling: engine.isReeling, tension: engine.strainTension, slack: engine.isSlack, phase: engine.phase, dt: dt)
        haptics.updateTension(engine.strainTension, active: engine.phase == .reeling)
        if save.settings.assist {
            let r = engine.round
            let ten = engine.phase == .reeling ? (r?.tension ?? 0) : 0
            let dist = (engine.phase == .reeling || engine.phase == .caught) ? max(0, r?.distance ?? 0) : 0
            if abs(ten - assistTension) > 0.5 { assistTension = ten }
            if abs(dist - assistDistance) > 0.5 { assistDistance = dist }
        }
    }

    // MARK: 시스템 알림 (전화, 이어폰 분리, 오디오 장치 변경)

    private func observeSystem() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor in self?.handleInterruption(raw) }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in self?.handleRouteChange(raw) }
        })
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started else { return }
                self.audio.restartAfterConfigurationChange()
            }
        })
    }

    private func handleInterruption(_ raw: UInt?) {
        guard started, let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            engine.abort(at: clock)
            speech.stop()
            audio.pause()
        case .ended:
            audio.resume()
            if phase == .idle && !showingMenu { audio.play(.ready, pan: 0) }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ raw: UInt?) {
        guard started, let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        // 이어폰이 빠지면 진행 중인 판을 멈춤 (HIG: 출력 장치 분리 시 재생 중단)
        if reason == .oldDeviceUnavailable, phase.isRoundActive {
            engine.abort(at: clock)
            speech.stop()
        }
    }
}

/// CADisplayLink가 컨트롤러를 강하게 잡지 않도록 하는 중계 객체 (메인 런루프에서 호출됨)
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var target: GameController?

    init(_ target: GameController) {
        self.target = target
    }

    @objc func tick(_ link: CADisplayLink) {
        target?.frame()
    }
}
