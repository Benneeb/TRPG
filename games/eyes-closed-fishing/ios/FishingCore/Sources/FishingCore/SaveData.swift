import Foundation

public struct GameSettings: Codable, Equatable, Sendable {
    public var bgmVolume: Float = 0.7
    public var sfxVolume: Float = 1
    public var voiceVolume: Float = 1
    public var failHint = true
    public var haptics = true
    public var doubleTapCast = false
    public var captions = true
    public var assist = false

    public init() {}

    // 새 설정 항목이 추가돼도 예전 저장 데이터를 읽을 수 있도록 누락 키는 기본값 사용
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        bgmVolume = try c.decodeIfPresent(Float.self, forKey: .bgmVolume) ?? d.bgmVolume
        sfxVolume = try c.decodeIfPresent(Float.self, forKey: .sfxVolume) ?? d.sfxVolume
        voiceVolume = try c.decodeIfPresent(Float.self, forKey: .voiceVolume) ?? d.voiceVolume
        failHint = try c.decodeIfPresent(Bool.self, forKey: .failHint) ?? d.failHint
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        doubleTapCast = try c.decodeIfPresent(Bool.self, forKey: .doubleTapCast) ?? d.doubleTapCast
        captions = try c.decodeIfPresent(Bool.self, forKey: .captions) ?? d.captions
        assist = try c.decodeIfPresent(Bool.self, forKey: .assist) ?? d.assist
    }
}

public struct FishRecord: Codable, Equatable, Sendable {
    public var count: Int
    public var maxSize: Int

    public init(count: Int = 0, maxSize: Int = 0) {
        self.count = count
        self.maxSize = maxSize
    }
}

public struct GameStats: Codable, Equatable, Sendable {
    public var totalCasts = 0
    public var totalCatches = 0
    public var perfectHooks = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCasts = try c.decodeIfPresent(Int.self, forKey: .totalCasts) ?? 0
        totalCatches = try c.decodeIfPresent(Int.self, forKey: .totalCatches) ?? 0
        perfectHooks = try c.decodeIfPresent(Int.self, forKey: .perfectHooks) ?? 0
    }
}

/// 기기에만 저장되는 데이터 (기획서 10장). 서버 전송 없음.
public struct SaveData: Codable, Equatable, Sendable {
    public var version = 1
    public var settings = GameSettings()
    public var stats = GameStats()
    /// SpeciesID.rawValue → 기록
    public var fish: [String: FishRecord] = [:]
    public var tutorialDone = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        settings = try c.decodeIfPresent(GameSettings.self, forKey: .settings) ?? GameSettings()
        stats = try c.decodeIfPresent(GameStats.self, forKey: .stats) ?? GameStats()
        fish = try c.decodeIfPresent([String: FishRecord].self, forKey: .fish) ?? [:]
        tutorialDone = try c.decodeIfPresent(Bool.self, forKey: .tutorialDone) ?? false
    }

    public func record(for id: SpeciesID) -> FishRecord {
        fish[id.rawValue] ?? FishRecord()
    }

    public var discoveredCount: Int {
        SpeciesID.allCases.filter { record(for: $0).count > 0 }.count
    }

    /// 기록 초기화: 설정은 유지하고 튜토리얼은 다시 보지 않음
    public mutating func resetRecords() {
        stats = GameStats()
        fish = [:]
    }
}
