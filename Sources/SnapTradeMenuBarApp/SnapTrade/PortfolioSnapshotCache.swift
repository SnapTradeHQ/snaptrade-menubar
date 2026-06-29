import Foundation

final class PortfolioSnapshotCache {
    private let key: String
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String, userDefaults: UserDefaults = .standard) {
        self.key = key
        self.userDefaults = userDefaults
    }

    func load() -> PortfolioSnapshot? {
        guard let data = userDefaults.data(forKey: key) else { return nil }
        return try? decoder.decode(PortfolioSnapshot.self, from: data)
    }

    func save(_ snapshot: PortfolioSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        userDefaults.set(data, forKey: key)
    }

    func delete() {
        userDefaults.removeObject(forKey: key)
    }
}
