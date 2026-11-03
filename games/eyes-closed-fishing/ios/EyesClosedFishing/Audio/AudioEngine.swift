import AVFoundation
import FishingCore
import os

/// 게임의 모든 소리를 담당합니다.
///
/// 구성:
/// ```
/// AmbientSynth ─┐
/// birdPlayer ───┴─ ambientMixer ─┐
/// ContinuousSynth ─┐             ├─ masterMixer ─ PeakLimiter ─ mainMixer ─ 출력
/// players[24] ─────┴─ sfxMixer ──┘
/// ```
/// 짧은 효과음은 앱 시작 시 FishingCore의 레시피로 미리 합성해 두고(`SoundBank`),
/// 장력에 따라 연속으로 변하는 소리는 `ContinuousSynth`가 실시간으로 만듭니다.
@MainActor
final class AudioEngine {
    static let sampleRate: Double = 44_100
    private static let log = Logger(subsystem: "EyesClosedFishing", category: "audio")

    private let engine = AVAudioEngine()
    private let ambientMixer = AVAudioMixerNode()
    private let sfxMixer = AVAudioMixerNode()
    private let masterMixer = AVAudioMixerNode()
    private let limiter: AVAudioUnitEffect
    private let birdPlayer = AVAudioPlayerNode()
    private var players: [AVAudioPlayerNode] = []
    private var nextPlayer = 0
    private let continuous = ContinuousSynth(sampleRate: AudioEngine.sampleRate)
    private let ambient = AmbientSynth(sampleRate: AudioEngine.sampleRate)
    private var continuousNode: AVAudioSourceNode!
    private var ambientNode: AVAudioSourceNode!

    private let mono = AVAudioFormat(standardFormatWithSampleRate: AudioEngine.sampleRate, channels: 1)!
    private let stereo = AVAudioFormat(standardFormatWithSampleRate: AudioEngine.sampleRate, channels: 2)!

    private var bank: [SoundKey: [AVAudioPCMBuffer]] = [:]
    private var variantCursor: [SoundKey: Int] = [:]
    private(set) var isBankReady = false
    private var isRunning = false

    // 배경음 덕킹
    private var duckHoldUntil: CFTimeInterval = 0
    private var duckDepth: Float = 1
    private var duckLevel: Float = 1
    private var nextBirdAt: CFTimeInterval = 0

    var bgmVolume: Float = 0.7
    var sfxVolume: Float = 1 { didSet { sfxMixer.outputVolume = sfxVolume } }

    init() {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        buildGraph()
    }

    private func buildGraph() {
        continuousNode = continuous.makeNode(format: mono)
        ambientNode = ambient.makeNode(format: stereo)
        let nodes: [AVAudioNode] = [ambientMixer, sfxMixer, masterMixer, birdPlayer, continuousNode, ambientNode, limiter]
        nodes.forEach { engine.attach($0) }

        engine.connect(ambientNode, to: ambientMixer, format: stereo)
        engine.connect(birdPlayer, to: ambientMixer, format: mono)
        engine.connect(continuousNode, to: sfxMixer, format: mono)
        for _ in 0..<24 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: sfxMixer, format: mono)
            players.append(p)
        }
        engine.connect(ambientMixer, to: masterMixer, format: stereo)
        engine.connect(sfxMixer, to: masterMixer, format: stereo)
        engine.connect(masterMixer, to: limiter, format: stereo)
        engine.connect(limiter, to: engine.mainMixerNode, format: stereo)
        ambientMixer.outputVolume = 0
        sfxMixer.outputVolume = sfxVolume
    }

    // MARK: 오디오 세션

    /// 소리가 곧 화면인 게임이므로 무음 스위치와 상관없이 재생(.playback)합니다.
    /// 다른 앱의 음악은 멈춥니다(섞이면 신호를 못 들음).
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredIOBufferDuration(0.005) // 입력→소리 지연 최소화
            try session.setActive(true)
        } catch {
            Self.log.error("audio session: \(error.localizedDescription)")
        }
    }

    // MARK: 효과음 미리 합성

    func prepareBank() async {
        guard !isBankReady else { return }
        let sr = Self.sampleRate
        let rendered: [SoundKey: [[Float]]] = await Task.detached(priority: .userInitiated) {
            var out: [SoundKey: [[Float]]] = [:]
            for key in SoundKey.allCases {
                out[key] = (0..<key.variantCount).map { SoundRecipes.render(key, variant: $0, sampleRate: sr).samples }
            }
            return out
        }.value
        for (key, variants) in rendered {
            bank[key] = variants.compactMap(makeBuffer)
        }
        isBankReady = true
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(samples.count)),
              let ch = buf.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { src in
            ch.update(from: src.baseAddress!, count: samples.count)
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        return buf
    }

    // MARK: 시작·정지

    func start() {
        guard !isRunning else { return }
        configureSession()
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            players.forEach { $0.play() }
            birdPlayer.play()
            nextBirdAt = CACurrentMediaTime() + Double.random(in: 5...10)
        } catch {
            Self.log.error("engine start: \(error.localizedDescription)")
        }
    }

    func pause() {
        guard isRunning else { return }
        silenceContinuous()
        engine.pause()
        isRunning = false
    }

    func resume() {
        start()
    }

    /// 장치 변경(이어폰 연결 등)으로 엔진이 멈췄을 때 다시 연결
    func restartAfterConfigurationChange() {
        isRunning = false
        start()
    }

    // MARK: 재생

    func play(_ cue: SoundCue, pan: Float) {
        guard isRunning else { return }
        let entry = cue.bankEntry
        play(key: entry.key, pan: pan, volume: entry.gain)
        switch cue {
        case .bite: duck(to: 0.3, hold: 0.8)
        case .catchSplash: duck(to: 0.35, hold: 1.2)
        default: break
        }
    }

    private func play(key: SoundKey, pan: Float, volume: Float, on node: AVAudioPlayerNode? = nil) {
        guard let variants = bank[key], !variants.isEmpty else { return }
        let i = variantCursor[key, default: Int.random(in: 0..<variants.count)]
        variantCursor[key] = (i + 1) % variants.count
        let player: AVAudioPlayerNode
        if let node {
            player = node
        } else {
            player = players[nextPlayer]
            nextPlayer = (nextPlayer + 1) % players.count
        }
        player.pan = max(-1, min(1, pan))
        player.volume = volume
        player.scheduleBuffer(variants[i], at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func duck(to depth: Float, hold: CFTimeInterval) {
        duckDepth = depth
        duckHoldUntil = CACurrentMediaTime() + hold
    }

    // MARK: 프레임 갱신

    /// 디스플레이 링크마다 호출: 연속음 파라미터, 덕킹, 새소리
    func update(reeling: Bool, tension: Double, slack: Bool, phase: Phase, dt: Double) {
        guard isRunning else { return }
        continuous.params.reeling = reeling ? 1 : 0
        continuous.params.tension = Float(tension)
        continuous.params.slack = slack ? 1 : 0

        let t = CACurrentMediaTime()
        var target: Float = phase == .reeling ? 0.6 : 1
        if t < duckHoldUntil { target = min(target, duckDepth) }
        let k = Float(1 - exp(-dt / (target < duckLevel ? 0.03 : 0.35)))
        duckLevel += (target - duckLevel) * k
        let ambientTarget = bgmVolume * 0.9 * duckLevel
        ambientMixer.outputVolume += (ambientTarget - ambientMixer.outputVolume) * min(1, Float(dt * 4))

        if t >= nextBirdAt {
            nextBirdAt = t + Double.random(in: 7...16)
            if phase != .bite && phase != .reeling {
                play(key: .bird, pan: Float.random(in: -0.9...0.9), volume: 1, on: birdPlayer)
            }
        }
    }

    func silenceContinuous() {
        continuous.params.reeling = 0
        continuous.params.tension = 0
        continuous.params.slack = 0
    }
}
