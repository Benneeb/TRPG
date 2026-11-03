import Foundation

/// SplitMix64 기반 난수. 시드를 고정하면 테스트에서 같은 판을 재현할 수 있습니다.
public final class RNG {
    private var state: UInt64

    public init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        state = seed
    }

    public func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// [0, 1)
    public func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    public func range(_ a: Double, _ b: Double) -> Double {
        a + unit() * (b - a)
    }

    public func range(_ r: ClosedRange<Double>) -> Double {
        range(r.lowerBound, r.upperBound)
    }

    /// 양 끝 포함 정수
    public func int(_ r: ClosedRange<Int>) -> Int {
        let span = r.upperBound - r.lowerBound + 1
        return r.lowerBound + min(span - 1, Int(unit() * Double(span)))
    }

    public func chance(_ p: Double) -> Bool {
        unit() < p
    }

    /// 표준정규분포 (Box–Muller)
    public func gaussian() -> Double {
        var u = 0.0
        while u <= .ulpOfOne { u = unit() }
        let v = unit()
        return (-2 * Foundation.log(u)).squareRoot() * cos(2 * .pi * v)
    }
}
