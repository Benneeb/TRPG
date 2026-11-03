import Foundation

/// 미리 그려 둘 효과음 종류. 하나의 키마다 변주 몇 개를 만들어 번갈아 재생합니다.
public enum SoundKey: Hashable, Sendable, CaseIterable {
    case cast, approach, nibble, frog, leaf, goldTick
    case bite(SpeciesID)
    case hookSet(perfect: Bool)
    case run, thrash, snap, hookFree, fleeEarly, missLate
    case catchSplash, record, ready, bird

    public static var allCases: [SoundKey] {
        var keys: [SoundKey] = [.cast, .approach, .nibble, .frog, .leaf, .goldTick]
        keys += SpeciesID.allCases.map { .bite($0) }
        keys += [.hookSet(perfect: false), .hookSet(perfect: true)]
        keys += [.run, .thrash, .snap, .hookFree, .fleeEarly, .missLate, .catchSplash, .record, .ready, .bird]
        return keys
    }

    /// 변주 개수: 자주 나오는 소리는 많이, 한 번 나오는 소리는 적게
    public var variantCount: Int {
        switch self {
        case .approach, .nibble, .thrash, .frog, .leaf, .bird: return 4
        case .bite, .run: return 3
        default: return 2
        }
    }
}

public extension SoundCue {
    /// 재생할 버퍼 키와 볼륨 배율
    var bankEntry: (key: SoundKey, gain: Float) {
        switch self {
        case .cast: return (.cast, 1)
        case .approach: return (.approach, 1)
        case .nibble: return (.nibble, 1)
        case .frog: return (.frog, 1)
        case .leaf: return (.leaf, 1)
        case .goldTick: return (.goldTick, 1)
        case let .bite(id): return (.bite(id), 1)
        case let .hookSet(perfect): return (.hookSet(perfect: perfect), 1)
        case .run: return (.run, 1)
        case let .thrash(volume): return (.thrash, volume)
        case .snap: return (.snap, 1)
        case .hookFree: return (.hookFree, 1)
        case .fleeEarly: return (.fleeEarly, 1)
        case .missLate: return (.missLate, 1)
        case .catchSplash: return (.catchSplash, 1)
        case .record: return (.record, 1)
        case .ready: return (.ready, 1)
        }
    }
}

/// 웹 프로토타입(Web Audio)과 같은 레시피로 효과음을 합성합니다.
public enum SoundRecipes {
    public static func render(_ key: SoundKey, variant: Int, sampleRate: Double = 44_100) -> SynthBuffer {
        let rng = RNG(seed: UInt64(truncatingIfNeeded: key.hashSeed &* 1_000_003 &+ variant))
        var b: SynthBuffer
        switch key {
        case .cast:
            b = SynthBuffer(duration: 1.5, sampleRate: sampleRate)
            b.noise(.bandpass, from: 380, to: 2600, q: 1.2, at: 0, attack: 0.12, decay: 0.3, volume: 0.32, rng: rng)
            for i in 0..<28 {
                let t = 0.25 + Double(i) * (0.012 + Double(i) * 0.0009)
                b.noise(.bandpass, from: 3400, q: 6, at: t, attack: 0.001, decay: 0.008,
                        volume: 0.11 * (1 - Double(i) / 28) + 0.005, rng: rng)
            }
            b.tone(from: 720, to: 160, at: 1.05, attack: 0.003, decay: 0.12, volume: 0.34)
            b.noise(.lowpass, from: 1500, to: 300, q: 0.7, at: 1.05, attack: 0.004, decay: 0.18, volume: 0.2, rng: rng)

        case .approach:
            b = SynthBuffer(duration: 0.8, sampleRate: sampleRate)
            var t = 0.0
            for _ in 0..<rng.int(2...4) {
                bubble(&b, at: t, rng: rng)
                t += rng.range(0.09, 0.17)
            }

        case .nibble:
            b = SynthBuffer(duration: 0.8, sampleRate: sampleRate)
            nibble(&b, at: 0, volume: 0.2, rng: rng)
            nibble(&b, at: rng.range(0.4, 0.6), volume: 0.16, rng: rng)

        case .frog:
            b = SynthBuffer(duration: 0.6, sampleRate: sampleRate)
            for g in 0..<2 {
                for i in 0..<6 {
                    let t = Double(g) * 0.24 + Double(i) * 0.024
                    b.tone(.saw, from: 230 - Double(g) * 30, to: 190 - Double(g) * 30, at: t,
                           attack: 0.003, decay: 0.018, volume: 0.06)
                }
            }

        case .leaf:
            b = SynthBuffer(duration: 0.1, sampleRate: sampleRate)
            b.noise(.highpass, from: 3500, q: 0.7, at: 0, attack: 0.001, decay: 0.015, volume: 0.06, rng: rng)
            b.tone(from: 900, to: 700, at: 0.005, attack: 0.002, decay: 0.02, volume: 0.045)

        case .goldTick:
            b = SynthBuffer(duration: 0.4, sampleRate: sampleRate)
            b.tone(from: 2093, at: 0, attack: 0.002, decay: 0.3, volume: 0.06)
            nibble(&b, at: 0, volume: 0.12, rng: rng)

        case let .bite(id):
            let sp = Species.named(id)
            b = SynthBuffer(duration: sp.isGold ? 1.6 : max(1.1, sp.bite.duration * 2.2), sampleRate: sampleRate)
            splash(&b, at: 0, volume: sp.bite.volume, duration: sp.bite.duration, frequency: sp.bite.frequency, rng: rng)
            b.tone(from: 140, to: 45, at: 0, attack: 0.003, decay: 0.3, volume: 0.55)
            if sp.isGold { chime(&b, at: 0.05, volume: 1.3) }

        case let .hookSet(perfect):
            b = SynthBuffer(duration: 0.35, sampleRate: sampleRate)
            b.noise(.bandpass, from: 700, to: 2400, q: 1.5, at: 0, attack: 0.01, decay: 0.12, volume: 0.25, rng: rng)
            if perfect { b.tone(from: 1760, at: 0.05, attack: 0.003, decay: 0.2, volume: 0.06) }

        case .run:
            b = SynthBuffer(duration: 0.9, sampleRate: sampleRate)
            splash(&b, at: 0, volume: 0.5, duration: 0.35, frequency: 1000, rng: rng)

        case .thrash:
            // 재생할 때 볼륨으로 거리감을 줌
            b = SynthBuffer(duration: 0.7, sampleRate: sampleRate)
            splash(&b, at: 0, volume: 1, duration: 0.24, frequency: 1350, rng: rng)

        case .snap:
            b = SynthBuffer(duration: 1.1, sampleRate: sampleRate)
            b.noise(.highpass, from: 2500, q: 0.7, at: 0, attack: 0.001, decay: 0.03, volume: 0.6, rng: rng)
            b.tone(.triangle, from: 1900, to: 1450, at: 0, attack: 0.002, decay: 0.6, volume: 0.25)
            b.tone(from: 3800, to: 3000, at: 0, attack: 0.002, decay: 0.4, volume: 0.08)
            splash(&b, at: 0.35, volume: 0.14, duration: 0.3, frequency: 1100, rng: rng)

        case .hookFree:
            b = SynthBuffer(duration: 0.8, sampleRate: sampleRate)
            b.tone(from: 320, to: 110, at: 0, attack: 0.003, decay: 0.1, volume: 0.3)
            splash(&b, at: 0.15, volume: 0.18, duration: 0.25, frequency: 1200, rng: rng)

        case .fleeEarly:
            // 첨벙 소리가 점점 작고 먹먹해지며 멀어짐
            b = SynthBuffer(duration: 1.1, sampleRate: sampleRate)
            splash(&b, at: 0, volume: 0.45, duration: 0.25, frequency: 1300, rng: rng)
            splash(&b, at: 0.22, volume: 0.22, duration: 0.2, frequency: 1000, rng: rng)
            splash(&b, at: 0.46, volume: 0.1, duration: 0.2, frequency: 750, rng: rng)

        case .missLate:
            b = SynthBuffer(duration: 1.0, sampleRate: sampleRate)
            for (i, f) in [600.0, 480, 380].enumerated() {
                b.tone(from: f, to: f * 0.5, at: Double(i) * 0.25, attack: 0.004, decay: 0.12, volume: 0.09)
            }
            b.noise(.lowpass, from: 900, to: 300, q: 0.5, at: 0, attack: 0.2, decay: 0.6, volume: 0.05, rng: rng)

        case .catchSplash:
            b = SynthBuffer(duration: 1.6, sampleRate: sampleRate)
            splash(&b, at: 0, volume: 0.9, duration: 0.8, frequency: 1100, rng: rng)
            for (i, f) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
                b.tone(.triangle, from: f, at: 0.55 + Double(i) * 0.09, attack: 0.004, decay: 0.45, volume: 0.13)
            }

        case .record:
            b = SynthBuffer(duration: 0.9, sampleRate: sampleRate)
            for (i, f) in [1318.5, 1568, 2093, 2637].enumerated() {
                b.tone(from: f, at: Double(i) * 0.07, attack: 0.003, decay: 0.5, volume: 0.06)
            }

        case .ready:
            b = SynthBuffer(duration: 0.15, sampleRate: sampleRate)
            b.tone(.triangle, from: 420, to: 390, at: 0, attack: 0.004, decay: 0.07, volume: 0.08)

        case .bird:
            b = SynthBuffer(duration: 1.0, sampleRate: sampleRate)
            var t = 0.0
            for _ in 0..<rng.int(2...4) {
                let base = rng.range(2600, 3400)
                b.tone(from: base * 1.3, to: base * 0.9, at: t, attack: 0.01, decay: 0.08, volume: rng.range(0.015, 0.03))
                t += rng.range(0.12, 0.2)
            }
        }
        b.limit()
        return b
    }

    // MARK: 공통 재료

    static func splash(_ b: inout SynthBuffer, at t: Double, volume v: Double, duration d: Double,
                       frequency f: Double, rng: RNG) {
        b.noise(.bandpass, from: f * 1.6, to: f * 0.45, q: 0.8, at: t, attack: 0.004, decay: d, volume: v, rng: rng)
        b.noise(.lowpass, from: f * 0.8, to: 220, q: 0.5, at: t + 0.01, attack: 0.01, decay: d * 1.4, volume: v * 0.5, rng: rng)
        b.tone(from: 150, to: 48, at: t, attack: 0.004, decay: d * 0.7, volume: v * 0.45)
        for _ in 0..<4 {
            b.tone(from: rng.range(900, 1500), to: rng.range(1800, 2500), at: t + d * 0.6 + rng.unit() * d,
                   attack: 0.002, decay: 0.035, volume: v * 0.07)
        }
    }

    static func bubble(_ b: inout SynthBuffer, at t: Double, rng: RNG) {
        let f0 = rng.range(240, 380)
        b.tone(from: f0, to: f0 * 4, at: t, attack: 0.004, decay: 0.07, volume: 0.15)
    }

    static func nibble(_ b: inout SynthBuffer, at t: Double, volume v: Double, rng: RNG) {
        b.tone(from: 1200, to: 640, at: t, attack: 0.002, decay: 0.03, volume: v)
        b.noise(.bandpass, from: 2200, q: 2, at: t, attack: 0.001, decay: 0.012, volume: v * 0.4, rng: rng)
    }

    static func chime(_ b: inout SynthBuffer, at t: Double, volume: Double) {
        for (f, v) in [(1568.0, 0.06), (2349.3, 0.04), (3136.0, 0.025)] {
            b.tone(from: f, at: t, attack: 0.002, decay: 1.3, volume: v * volume)
        }
    }
}

extension SoundKey {
    /// 실행마다 바뀌지 않는 시드 (Hashable.hashValue는 실행마다 달라지므로 쓰지 않음)
    var hashSeed: Int {
        switch self {
        case .cast: return 1
        case .approach: return 2
        case .nibble: return 3
        case .frog: return 4
        case .leaf: return 5
        case .goldTick: return 6
        case let .bite(id): return 10 + (SpeciesID.allCases.firstIndex(of: id) ?? 0)
        case let .hookSet(perfect): return perfect ? 21 : 20
        case .run: return 30
        case .thrash: return 31
        case .snap: return 32
        case .hookFree: return 33
        case .fleeEarly: return 34
        case .missLate: return 35
        case .catchSplash: return 36
        case .record: return 37
        case .ready: return 38
        case .bird: return 39
        }
    }
}
