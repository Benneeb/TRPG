import AVFoundation
import FishingCore

/// 메인 스레드가 쓰고 오디오 스레드가 읽는 값.
/// 정렬된 32비트 Float의 읽기·쓰기는 arm64에서 원자적이므로 잠금 없이 공유합니다.
/// (값이 한 버퍼 늦게 반영돼도 귀로는 구분되지 않음)
final class ContinuousParams {
    private let storage = UnsafeMutablePointer<Float>.allocate(capacity: 4)

    init() { storage.initialize(repeating: 0, count: 4) }
    deinit { storage.deallocate() }

    /// 릴을 감는 중이면 1
    var reeling: Float {
        get { storage[0] }
        set { storage[0] = newValue }
    }
    /// 0~110 장력 (마찰음 음높이)
    var tension: Float {
        get { storage[1] }
        set { storage[1] = newValue }
    }
    /// 줄이 느슨하면 1
    var slack: Float {
        get { storage[2] }
        set { storage[2] = newValue }
    }
}

/// 실시간으로 변하는 소리: 릴 래칫, 릴 바닥음, 낚싯줄 마찰음, 느슨한 줄 경고음.
/// 렌더 콜백 안에서는 메모리 할당·잠금·Objective-C 호출을 하지 않습니다.
final class ContinuousSynth {
    let params = ContinuousParams()
    private let sampleRate: Double

    // 렌더 스레드 전용 상태
    private var rngState: UInt64 = 0x1234_5678_9ABC_DEF0
    private var humPhase = 0.0
    private var humLP: Biquad
    private var humGain = 0.0
    private var clickTimer = 0.0
    private var clickSamplesLeft = 0
    private var clickLength = 1
    private var clickBP = Biquad()
    private var strainPhase1 = 0.0
    private var strainPhase2 = 0.0
    private var vibPhase = 0.0
    private var strainFreq = 300.0
    private var strainGain = 0.0
    private var strainBP: Biquad
    private var coefCounter = 0
    private var slackPhase = 0.0
    private var slackAMPhase = 0.0
    private var slackGain = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        humLP = Biquad(.lowpass, frequency: 220, q: 0.707, sampleRate: sampleRate)
        strainBP = Biquad(.bandpass, frequency: 660, q: 5, sampleRate: sampleRate)
        clickLength = max(1, Int(0.006 * sampleRate))
    }

    @inline(__always)
    private func white() -> Double {
        rngState ^= rngState << 13
        rngState ^= rngState >> 7
        rngState ^= rngState << 17
        return Double(rngState >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1
    }

    func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            self.render(frameCount: Int(frameCount), audioBufferList)
            return noErr
        }
    }

    private func render(frameCount: Int, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard let first = buffers.first, let out = first.mData?.assumingMemoryBound(to: Float.self) else { return }

        let reeling = Double(params.reeling) > 0.5
        let tension = Double(params.tension)
        let slack = Double(params.slack) > 0.5
        let load = min(1.1, max(0, tension / 100))

        // 장력 → 마찰음 목표값 (버퍼마다 한 번 계산)
        let x = min(1.2, max(0, (tension - 50) / 50))
        let strainTargetGain = tension < 50 ? 0 : pow(x, 1.4) * 0.24
        let strainTargetFreq = 300 * pow(2, x * 2.3)
        let humTarget = reeling ? 0.05 : 0
        let slackTarget = slack ? 0.07 : 0
        let smooth = 1 - exp(-1 / (sampleRate * 0.03))
        let slowSmooth = 1 - exp(-1 / (sampleRate * 0.08))
        let clickInterval = 1 / (26 - load * 10)
        let invSR = 1 / sampleRate

        for i in 0..<frameCount {
            humGain += (humTarget - humGain) * smooth
            strainGain += (strainTargetGain - strainGain) * smooth
            strainFreq += (strainTargetFreq - strainFreq) * smooth
            slackGain += (slackTarget - slackGain) * slowSmooth

            var sample = 0.0

            // 릴 바닥음 (드르륵의 몸통)
            if humGain > 0.0005 {
                humPhase += 52 * invSR
                if humPhase >= 1 { humPhase -= 1 }
                sample += humLP.process(oscillator(.saw, phase: humPhase, dt: 52 * invSR)) * humGain
            }

            // 래칫 클릭
            if reeling {
                clickTimer -= invSR
                if clickTimer <= 0 {
                    clickTimer += clickInterval
                    clickSamplesLeft = clickLength
                    clickBP.set(.bandpass, frequency: 2600 - load * 900 + white() * 150, q: 5, sampleRate: sampleRate)
                }
            } else {
                clickTimer = 0
            }
            if clickSamplesLeft > 0 {
                let env = Double(clickSamplesLeft) / Double(clickLength)
                sample += clickBP.process(white()) * env * env * 0.9
                clickSamplesLeft -= 1
            }

            // 낚싯줄 마찰음: 톱니+사각파 → 공명 필터, 비브라토로 끼이익
            if strainGain > 0.0005 {
                vibPhase += 7.5 * invSR
                if vibPhase >= 1 { vibPhase -= 1 }
                let vib = sin(2 * .pi * vibPhase) * strainFreq * 0.012
                let f1 = (strainFreq + vib) * invSR
                let f2 = (strainFreq * 1.006 + vib) * invSR
                strainPhase1 += f1
                if strainPhase1 >= 1 { strainPhase1 -= 1 }
                strainPhase2 += f2
                if strainPhase2 >= 1 { strainPhase2 -= 1 }
                let osc = oscillator(.saw, phase: strainPhase1, dt: f1) + 0.35 * oscillator(.square, phase: strainPhase2, dt: f2)
                coefCounter += 1
                if coefCounter >= 32 {
                    coefCounter = 0
                    strainBP.set(.bandpass, frequency: strainFreq * 2.2, q: 5, sampleRate: sampleRate)
                }
                sample += strainBP.process(osc) * strainGain
            }

            // 느슨한 줄: 낮게 흔들리는 소리
            if slackGain > 0.0005 {
                slackPhase += 82 * invSR
                if slackPhase >= 1 { slackPhase -= 1 }
                slackAMPhase += 2.6 * invSR
                if slackAMPhase >= 1 { slackAMPhase -= 1 }
                let am = 0.5 + 0.5 * sin(2 * .pi * slackAMPhase)
                sample += sin(2 * .pi * slackPhase) * am * slackGain
            }

            out[i] = Float(sample)
        }
        // 모노 포맷이지만 혹시 채널이 더 있으면 복사
        for b in 1..<max(1, buffers.count) {
            if let dst = buffers[b].mData?.assumingMemoryBound(to: Float.self) {
                dst.update(from: out, count: frameCount)
            }
        }
    }
}

/// 낚시터 배경음: 잔잔한 물소리(갈색 소음) + 찰랑이는 높은 결. 좌우 채널을 따로 만들어 공간감을 줍니다.
final class AmbientSynth {
    private let sampleRate: Double
    private var rng: (UInt64, UInt64) = (0xDEAD_BEEF_1234_5678, 0x0BAD_F00D_8765_4321)
    private var brown: (Double, Double) = (0, 0)
    private var bodyLP: (Biquad, Biquad)
    private var shimmerBP: (Biquad, Biquad)
    private var lfo1 = 0.0
    private var lfo2 = 0.37

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bodyLP = (Biquad(.lowpass, frequency: 480, q: 0.707, sampleRate: sampleRate),
                  Biquad(.lowpass, frequency: 480, q: 0.707, sampleRate: sampleRate))
        shimmerBP = (Biquad(.bandpass, frequency: 1300, q: 0.6, sampleRate: sampleRate),
                     Biquad(.bandpass, frequency: 1300, q: 0.6, sampleRate: sampleRate))
    }

    @inline(__always)
    private static func xorshift(_ s: inout UInt64) -> Double {
        s ^= s << 13
        s ^= s >> 7
        s ^= s << 17
        return Double(s >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1
    }

    func makeNode(format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, audioBufferList -> OSStatus in
            self.render(frameCount: Int(frameCount), audioBufferList)
            return noErr
        }
    }

    private func render(frameCount: Int, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard let lp = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return }
        let rp = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
        let invSR = 1 / sampleRate
        for i in 0..<frameCount {
            lfo1 += 0.11 * invSR
            if lfo1 >= 1 { lfo1 -= 1 }
            lfo2 += 0.23 * invSR
            if lfo2 >= 1 { lfo2 -= 1 }
            let bodyAmp = 0.5 + 0.18 * sin(2 * .pi * lfo1)
            let shimAmp = 0.022 + 0.014 * sin(2 * .pi * lfo2)

            let wl = Self.xorshift(&rng.0)
            let wr = Self.xorshift(&rng.1)
            brown.0 = (brown.0 + 0.02 * wl) / 1.02
            brown.1 = (brown.1 + 0.02 * wr) / 1.02
            let l = bodyLP.0.process(brown.0 * 3.5) * bodyAmp + shimmerBP.0.process(wl) * shimAmp
            let r = bodyLP.1.process(brown.1 * 3.5) * bodyAmp + shimmerBP.1.process(wr) * shimAmp
            lp[i] = Float(l)
            rp?[i] = Float(r)
        }
    }
}
