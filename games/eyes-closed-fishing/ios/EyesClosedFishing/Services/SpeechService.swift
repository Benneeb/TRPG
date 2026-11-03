import AVFoundation

/// 음성 안내 (기획서 4.5). 기기에 설치된 한국어 음성 중 가장 품질 좋은 것을 씁니다.
@MainActor
final class SpeechService: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var current: (id: Int, utterance: ObjectIdentifier)?
    private var fallbackTask: Task<Void, Never>?
    private lazy var voice: AVSpeechSynthesisVoice? = Self.bestKoreanVoice()

    /// 재생이 끝나면 엔진에 알릴 콜백
    var onFinish: ((Int) -> Void)?
    var volume: Float = 1

    override init() {
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    private static func bestKoreanVoice() -> AVSpeechSynthesisVoice? {
        let ko = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ko-KR" }
        return ko.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "ko-KR")
    }

    func speak(id: Int, text: String) {
        stop()
        // 음성 볼륨을 0으로 둔 경우에도 자막 시간만큼 기다린 뒤 진행
        guard volume > 0.01 else {
            finishLater(id: id, after: max(1.2, Double(text.count) * 0.12))
            return
        }
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        u.volume = volume
        u.preUtteranceDelay = 0
        u.postUtteranceDelay = 0.05
        current = (id, ObjectIdentifier(u))
        synthesizer.speak(u)
    }

    func stop() {
        fallbackTask?.cancel()
        fallbackTask = nil
        current = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func finishLater(id: Int, after seconds: Double) {
        current = nil
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.onFinish?(id)
        }
    }

    private func handleFinished(_ utterance: ObjectIdentifier) {
        guard let c = current, c.utterance == utterance else { return }
        current = nil
        onFinish?(c.id)
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.handleFinished(id) }
    }
}
