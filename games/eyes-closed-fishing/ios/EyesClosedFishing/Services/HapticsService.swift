import CoreHaptics
import FishingCore
import UIKit

/// 진동은 소리를 보강하는 보조 피드백 (기획서 6.4).
/// 입질·챔질 등은 짧은 패턴, 장력 경고는 세기가 연속으로 변하는 진동으로 표현합니다.
@MainActor
final class HapticsService {
    private var engine: CHHapticEngine?
    private var tensionPlayer: CHHapticAdvancedPatternPlayer?
    private var tensionIntensity: Float = 0
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)

    var enabled = true {
        didSet { if !enabled { stopTension() } }
    }

    func start() {
        guard supportsHaptics else { fallback.prepare(); return }
        if engine == nil {
            do {
                let e = try CHHapticEngine()
                e.playsHapticsOnly = true
                e.isAutoShutdownEnabled = false
                e.resetHandler = { [weak self] in
                    Task { @MainActor in
                        self?.tensionPlayer = nil
                        self?.tensionIntensity = 0
                        try? self?.engine?.start()
                    }
                }
                e.stoppedHandler = { [weak self] _ in
                    Task { @MainActor in
                        self?.tensionPlayer = nil
                        self?.tensionIntensity = 0
                    }
                }
                engine = e
            } catch {
                engine = nil
                return
            }
        }
        try? engine?.start()
    }

    func stop() {
        stopTension()
        engine?.stop(completionHandler: nil)
    }

    func play(_ cue: HapticCue) {
        guard enabled else { return }
        guard supportsHaptics, let engine else {
            fallback.impactOccurred()
            return
        }
        let events: [CHHapticEvent]
        switch cue {
        case .bite:
            events = [transient(1.0, 0.8, at: 0)]
        case .hookSet:
            events = [transient(0.7, 0.6, at: 0), transient(0.7, 0.6, at: 0.07)]
        case .run:
            events = [transient(0.8, 0.3, at: 0), continuous(0.5, 0.2, at: 0.02, duration: 0.2)]
        case .snap:
            events = [transient(1.0, 1.0, at: 0), continuous(0.9, 0.4, at: 0.02, duration: 0.2), transient(1.0, 0.8, at: 0.26)]
        case .caught:
            events = [continuous(0.6, 0.2, at: 0, duration: 0.4)]
        }
        do {
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // 진동 실패는 게임 진행에 영향 없음
        }
    }

    /// 장력 60 미만: 없음, 60~85: 약하게, 85 이상: 강하게 (매 프레임 호출)
    func updateTension(_ tension: Double, active: Bool) {
        guard enabled, supportsHaptics, let engine else { return }
        let target: Float
        if !active || tension < 60 { target = 0 }
        else if tension < 85 { target = 0.18 + Float((tension - 60) / 25) * 0.2 }
        else { target = 0.9 }

        if target == 0 {
            stopTension()
            return
        }
        if tensionPlayer == nil {
            do {
                let event = CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                    ],
                    relativeTime: 0,
                    duration: 30
                )
                let p = try engine.makeAdvancedPlayer(with: CHHapticPattern(events: [event], parameters: []))
                p.loopEnabled = true
                try p.start(atTime: CHHapticTimeImmediate)
                tensionPlayer = p
                tensionIntensity = -1
            } catch {
                return
            }
        }
        guard abs(target - tensionIntensity) > 0.03 else { return }
        tensionIntensity = target
        let param = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: target, relativeTime: 0)
        try? tensionPlayer?.sendParameters([param], atTime: CHHapticTimeImmediate)
    }

    private func stopTension() {
        guard let p = tensionPlayer else { return }
        try? p.stop(atTime: CHHapticTimeImmediate)
        tensionPlayer = nil
        tensionIntensity = 0
    }

    private func transient(_ intensity: Float, _ sharpness: Float, at t: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    private func continuous(_ intensity: Float, _ sharpness: Float, at t: TimeInterval, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t, duration: duration)
    }
}
