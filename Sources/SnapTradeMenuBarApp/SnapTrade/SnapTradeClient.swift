import Foundation

@MainActor
final class SnapTradeClient {
    private let config: AppConfig
    private let session: URLSession
    private let decoder: JSONDecoder

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .useDefaultKeys
    }

    func accounts(accessToken: String) async throws -> [SnapTradeAccount] {
        try await get(
            path: "/accounts",
            accessToken: accessToken
        )
    }

    func accountDetails(accountID: String, accessToken: String) async throws -> SnapTradeAccount {
        try await get(path: "/accounts/\(accountID)", accessToken: accessToken)
    }

    func positions(accountID: String, accessToken: String) async throws -> [SnapTradePosition] {
        let response: AllAccountPositionsResponse = try await get(
            path: "/accounts/\(accountID)/positions/all",
            accessToken: accessToken
        )
        return response.results
    }

    func balances(accountID: String, accessToken: String) async throws -> [MoneyValue] {
        try await get(
            path: "/accounts/\(accountID)/balances",
            accessToken: accessToken
        )
    }

    func authorizations(accessToken: String) async throws -> [SnapTradeAuthorization] {
        try await get(path: "/authorizations", accessToken: accessToken)
    }

    private func get<T: Decodable>(path: String, accessToken: String) async throws -> T {
        guard let url = URL(string: config.apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw SnapTradeClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SnapTradeClientError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw SnapTradeClientError.decodingFailed(path)
            }
        case 401:
            throw SnapTradeClientError.unauthorized
        case 404:
            throw SnapTradeClientError.notFound
        default:
            throw SnapTradeClientError.httpStatus(http.statusCode)
        }
    }
}

private struct AllAccountPositionsResponse: Decodable {
    let results: [SnapTradePosition]
    let dataFreshness: DataFreshness

    enum CodingKeys: String, CodingKey {
        case results
        case dataFreshness = "data_freshness"
    }
}

private struct DataFreshness: Decodable {
    let asOf: String?

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.asOf = try container.decodeIfPresent(String.self, forKey: .asOf)
    }
}

enum SnapTradeClientError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case httpStatus(Int)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "SnapTrade API URL is invalid."
        case .invalidResponse:
            return "SnapTrade API returned an invalid response."
        case .unauthorized:
            return "SnapTrade access token was rejected."
        case .notFound:
            return "SnapTrade endpoint was not found."
        case .httpStatus(let status):
            return "SnapTrade API request failed with HTTP \(status)."
        case .decodingFailed(let path):
            return "SnapTrade API response for \(path) was not in the expected format."
        }
    }
}
