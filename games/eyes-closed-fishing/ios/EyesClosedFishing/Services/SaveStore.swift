import FishingCore
import Foundation

/// 기록과 설정을 기기 안(UserDefaults)에만 저장합니다. 네트워크 전송 없음.
struct SaveStore {
    private let key = "eyes-closed-fishing.save.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SaveData {
        guard let data = defaults.data(forKey: key),
              let save = try? JSONDecoder().decode(SaveData.self, from: data) else {
            return SaveData()
        }
        return save
    }

    func save(_ save: SaveData) {
        guard let data = try? JSONEncoder().encode(save) else { return }
        defaults.set(data, forKey: key)
    }
}
