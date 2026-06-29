import Foundation

final class UserDefaultsTokenStore: TokenStore {
    private let key: String
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    func load() throws -> TokenSet? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        return try decoder.decode(TokenSet.self, from: data)
    }

    func save(_ tokenSet: TokenSet) throws {
        let data = try encoder.encode(tokenSet)
        defaults.set(data, forKey: key)
    }

    func delete() throws {
        defaults.removeObject(forKey: key)
    }
}
