import Foundation

public enum SpeciesID: String, Codable, CaseIterable, Sendable {
    case crucian, carp, bass, catfish, goldCarp
}

public struct BiteSound: Sendable, Equatable {
    public let frequency: Double
    public let volume: Double
    public let duration: Double
}

/// 어종 파라미터 (기획서 5.2 초기 튜닝값)
/// - rise/fall: 초당 장력 변화, reel: 누를 때 초당 거리 감소, resist: 뗐을 때 초당 거리 증가
public struct Species: Sendable, Equatable {
    public let id: SpeciesID
    public let name: String
    public let grade: String
    public let weight: Double
    public let size: ClosedRange<Int>
    public let wait: ClosedRange<Double>
    public let preSignals: ClosedRange<Int>
    public let silence: ClosedRange<Double>?
    public let hookWindow: Double
    public let rise: Double
    public let fall: Double
    public let reel: Double
    public let resist: Double
    public let runGap: ClosedRange<Double>?
    public let runDuration: ClosedRange<Double>
    public let runPush: Double
    public let runPull: Double
    public let isGold: Bool
    public let bite: BiteSound

    public static let all: [Species] = [
        Species(id: .crucian, name: "붕어", grade: "흔함", weight: 45, size: 10...35,
                wait: 6...12, preSignals: 2...4, silence: 0.8...1.5, hookWindow: 1.4,
                rise: 15, fall: 45, reel: 10, resist: 2,
                runGap: nil, runDuration: 0...0, runPush: 0, runPull: 0, isGold: false,
                bite: BiteSound(frequency: 1500, volume: 0.8, duration: 0.36)),
        Species(id: .carp, name: "잉어", grade: "보통", weight: 25, size: 30...80,
                wait: 5...10, preSignals: 1...3, silence: 0.6...1.2, hookWindow: 1.2,
                rise: 22, fall: 38, reel: 12, resist: 4,
                runGap: 4...7, runDuration: 1...1.8, runPush: 18, runPull: 4, isGold: false,
                bite: BiteSound(frequency: 1150, volume: 1, duration: 0.46)),
        Species(id: .bass, name: "배스", grade: "보통", weight: 22, size: 20...60,
                wait: 4...8, preSignals: 0...1, silence: nil, hookWindow: 0.9,
                rise: 30, fall: 42, reel: 15, resist: 4,
                runGap: 2...4, runDuration: 0.6...1.2, runPush: 26, runPull: 6, isGold: false,
                bite: BiteSound(frequency: 1900, volume: 1, duration: 0.28)),
        Species(id: .catfish, name: "메기", grade: "희귀", weight: 7.5, size: 40...110,
                wait: 7...12, preSignals: 2...3, silence: 1.5...2.5, hookWindow: 1.2,
                rise: 18, fall: 22, reel: 9, resist: 3,
                runGap: 7...11, runDuration: 2...3, runPush: 12, runPull: 5, isGold: false,
                bite: BiteSound(frequency: 620, volume: 1, duration: 0.55)),
        Species(id: .goldCarp, name: "황금 잉어", grade: "전설", weight: 0.5, size: 50...90,
                wait: 5...10, preSignals: 3...3, silence: 0.8...1.2, hookWindow: 1.0,
                rise: 26, fall: 32, reel: 13, resist: 5,
                runGap: 2.5...4.5, runDuration: 0.8...1.5, runPush: 22, runPull: 6, isGold: true,
                bite: BiteSound(frequency: 1300, volume: 1, duration: 0.45)),
    ]

    public static func named(_ id: SpeciesID) -> Species {
        all.first { $0.id == id }!
    }
}
