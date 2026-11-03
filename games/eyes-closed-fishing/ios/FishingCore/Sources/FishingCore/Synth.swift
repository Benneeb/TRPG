import Foundation

public enum Wave: Sendable {
    case sine, saw, square, triangle
}

public enum FilterKind: Sendable {
    case lowpass, highpass, bandpass
}

/// RBJ 쿡북 바이쿼드 필터 (Web Audio BiquadFilterNode와 같은 정의)
public struct Biquad: Sendable {
    private var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    private var z1 = 0.0, z2 = 0.0

    public init() {}

    public init(_ kind: FilterKind, frequency: Double, q: Double, sampleRate: Double) {
        set(kind, frequency: frequency, q: q, sampleRate: sampleRate)
    }

    public mutating func set(_ kind: FilterKind, frequency: Double, q: Double, sampleRate: Double) {
        let f = min(max(frequency, 10), sampleRate * 0.45)
        let w0 = 2 * Double.pi * f / sampleRate
        let cosw = cos(w0)
        let alpha = sin(w0) / (2 * max(q, 0.0001))
        var nb0: Double, nb1: Double, nb2: Double
        switch kind {
        case .lowpass:
            nb0 = (1 - cosw) / 2; nb1 = 1 - cosw; nb2 = (1 - cosw) / 2
        case .highpass:
            nb0 = (1 + cosw) / 2; nb1 = -(1 + cosw); nb2 = (1 + cosw) / 2
        case .bandpass:
            nb0 = alpha; nb1 = 0; nb2 = -alpha
        }
        let a0 = 1 + alpha
        b0 = nb0 / a0; b1 = nb1 / a0; b2 = nb2 / a0
        a1 = (-2 * cosw) / a0
        a2 = (1 - alpha) / a0
    }

    @inline(__always)
    public mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// 밴드 제한 오실레이터 보정 (PolyBLEP)
@inline(__always)
public func polyBlep(_ t: Double, _ dt: Double) -> Double {
    if t < dt {
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        let x = (t - 1) / dt
        return x * x + x + x + 1
    }
    return 0
}

@inline(__always)
public func oscillator(_ wave: Wave, phase: Double, dt: Double) -> Double {
    switch wave {
    case .sine:
        return sin(2 * .pi * phase)
    case .saw:
        return 2 * phase - 1 - polyBlep(phase, dt)
    case .square:
        var p2 = phase + 0.5
        if p2 >= 1 { p2 -= 1 }
        return (phase < 0.5 ? 1 : -1) + polyBlep(phase, dt) - polyBlep(p2, dt)
    case .triangle:
        return 4 * abs(phase - 0.5) - 1
    }
}

/// 짧은 효과음을 미리 그려 두는 모노 버퍼.
/// 엔벨로프·주파수 변화는 Web Audio의 지수 램프와 같은 모양입니다.
public struct SynthBuffer: Sendable {
    public let sampleRate: Double
    public private(set) var samples: [Float]

    public init(duration: Double, sampleRate: Double = 44_100) {
        self.sampleRate = sampleRate
        samples = [Float](repeating: 0, count: max(1, Int(duration * sampleRate)))
    }

    public var duration: Double { Double(samples.count) / sampleRate }

    @inline(__always)
    private static func envelope(_ tau: Double, attack a: Double, decay d: Double, volume v: Double) -> Double {
        let floor = 0.0001
        let peak = max(v, 0.0002)
        if tau < a {
            return floor * pow(peak / floor, tau / a)
        }
        return peak * pow(floor / peak, min(1, (tau - a) / d))
    }

    public mutating func tone(_ wave: Wave = .sine, from f0: Double, to f1: Double? = nil,
                              at t: Double, attack a: Double = 0.005, decay d: Double = 0.1,
                              volume: Double) {
        let start = Int(t * sampleRate)
        let length = Int((a + d) * sampleRate)
        guard start >= 0, start < samples.count else { return }
        let end = min(samples.count, start + length)
        var phase = 0.0
        let total = a + d
        for i in start..<end {
            let tau = Double(i - start) / sampleRate
            let f = f1.map { f0 * pow($0 / f0, tau / total) } ?? f0
            let dt = f / sampleRate
            let s = oscillator(wave, phase: phase, dt: dt)
            phase += dt
            if phase >= 1 { phase -= floor(phase) }
            samples[i] += Float(s * Self.envelope(tau, attack: a, decay: d, volume: volume))
        }
    }

    public mutating func noise(_ kind: FilterKind, from f0: Double, to f1: Double? = nil, q: Double = 1,
                               at t: Double, attack a: Double = 0.003, decay d: Double = 0.05,
                               volume: Double, rng: RNG) {
        let start = Int(t * sampleRate)
        let length = Int((a + d) * sampleRate)
        guard start >= 0, start < samples.count else { return }
        let end = min(samples.count, start + length)
        var filter = Biquad(kind, frequency: f0, q: q, sampleRate: sampleRate)
        let total = a + d
        for i in start..<end {
            let tau = Double(i - start) / sampleRate
            if let f1, (i - start) % 16 == 0 {
                filter.set(kind, frequency: f0 * pow(f1 / f0, tau / total), q: q, sampleRate: sampleRate)
            }
            let white = rng.unit() * 2 - 1
            let s = filter.process(white)
            samples[i] += Float(s * Self.envelope(tau, attack: a, decay: d, volume: volume))
        }
    }

    public var peak: Float {
        samples.reduce(0) { max($0, abs($1)) }
    }

    /// 클리핑 방지: 최대값이 limit을 넘을 때만 줄임
    public mutating func limit(to limit: Float = 0.98) {
        let p = peak
        guard p > limit else { return }
        let g = limit / p
        for i in samples.indices { samples[i] *= g }
    }
}
