import Foundation
import CryptoKit

struct AppConfig: Codable, Equatable {
    var environment: SnapTradeEnvironment
    var clientID: String
    var redirectMode: RedirectMode
    var refreshInterval: RefreshInterval
    var scope: String
    var authorizationEndpoint: String
    var tokenEndpoint: String
    var revokeEndpoint: String
    var metadataEndpoint: String
    var apiBaseURL: String

    // Set only after verifying a claimed production public-native OAuth application.
    static let productionClientID: String? = "JSuxSu887CLm80FO3lgqmN-32FsGtD1X"
    static let legacyTestClientID = "OqgWgrKIfojI7ZhONa0xe8fRuqMuvKKE7Grn3H5r"

    static func load(defaults: UserDefaults = .standard,
                     environment: [String: String] = ProcessInfo.processInfo.environment,
                     productionClientID: String? = AppConfig.productionClientID) -> AppConfig {
        let saved = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(AppConfig.self, from: $0) }
        var config = saved ?? AppConfig.defaults
        if let productionClientID, !productionClientID.isEmpty,
           config.environment == .production,
           config.authorizationEndpoint == SnapTradeEnvironment.production.defaultAuthorizationEndpoint,
           config.tokenEndpoint == SnapTradeEnvironment.production.defaultTokenEndpoint,
           config.metadataEndpoint == SnapTradeEnvironment.production.defaultMetadataEndpoint,
           config.apiBaseURL == SnapTradeEnvironment.production.defaultAPIBaseURL,
           config.clientID.isEmpty || config.clientID == legacyTestClientID {
            config.clientID = productionClientID
        }
        if config.clientID.isEmpty { config.clientID = productionClientID ?? defaultClientID }
        config.redirectMode = .fixed18787
        if !defaults.bool(forKey: hourlyRefreshMigrationKey) {
            if config.refreshInterval == .fifteenMinutes { config.refreshInterval = .oneHour }
            defaults.set(true, forKey: hourlyRefreshMigrationKey)
        }
        // Persist the base configuration, never temporary process overrides.
        config.save(defaults: defaults)
        return config.withEnvironmentOverrides(environment)
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    // Bind both tokens and cached portfolios to the complete OAuth/API context.
    // Old environment-only storage is deliberately never imported or deleted.
    var sessionStorageID: String {
        let context = [environment.rawValue, clientID, authorizationEndpoint, tokenEndpoint,
                       revokeEndpoint, metadataEndpoint, apiBaseURL, scope, redirectMode.rawValue]
        let data = try! JSONEncoder().encode(context)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func authorizationURL() throws -> URL {
        guard let url = URL(string: authorizationEndpoint) else {
            throw OAuthProviderError.invalidEndpoint
        }
        return url
    }

    func tokenURL() throws -> URL {
        guard let url = URL(string: tokenEndpoint) else {
            throw OAuthProviderError.invalidEndpoint
        }
        return url
    }

    private func withEnvironmentOverrides(_ env: [String: String]) -> AppConfig {
        var copy = self
        copy.clientID = env["SNAPTRADE_CLIENT_ID"] ?? clientID
        copy.authorizationEndpoint = env["SNAPTRADE_AUTHORIZE_URL"] ?? authorizationEndpoint
        copy.tokenEndpoint = env["SNAPTRADE_TOKEN_URL"] ?? tokenEndpoint
        copy.revokeEndpoint = env["SNAPTRADE_REVOKE_URL"] ?? revokeEndpoint
        copy.metadataEndpoint = env["SNAPTRADE_OAUTH_METADATA_URL"] ?? metadataEndpoint
        copy.apiBaseURL = env["SNAPTRADE_API_BASE_URL"] ?? apiBaseURL
        copy.scope = env["SNAPTRADE_SCOPE"] ?? scope
        return copy
    }

    var fallbackOAuthMetadata: OAuthAuthorizationServerMetadata {
        OAuthAuthorizationServerMetadata(
            issuer: environment.defaultOAuthIssuer,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            deviceAuthorizationEndpoint: nil,
            revocationEndpoint: revokeEndpoint.isEmpty ? nil : revokeEndpoint,
            registrationEndpoint: environment.defaultRegistrationEndpoint,
            scopesSupported: ["read"],
            grantTypesSupported: ["authorization_code", "refresh_token"],
            codeChallengeMethodsSupported: ["S256"],
            tokenEndpointAuthMethodsSupported: ["none"]
        )
    }

    private static let storageKey = "SnapTradeMenuBar.AppConfig.v1"
    private static let hourlyRefreshMigrationKey = "SnapTradeMenuBar.HourlyRefreshMigration.v1"
    private static let defaultClientID = productionClientID ?? legacyTestClientID

    static let defaults = AppConfig(
        environment: .production,
        clientID: defaultClientID,
        redirectMode: .fixed18787,
        refreshInterval: .oneHour,
        scope: "read",
        authorizationEndpoint: SnapTradeEnvironment.production.defaultAuthorizationEndpoint,
        tokenEndpoint: SnapTradeEnvironment.production.defaultTokenEndpoint,
        revokeEndpoint: SnapTradeEnvironment.production.defaultRevokeEndpoint,
        metadataEndpoint: SnapTradeEnvironment.production.defaultMetadataEndpoint,
        apiBaseURL: SnapTradeEnvironment.production.defaultAPIBaseURL
    )
}

enum SnapTradeEnvironment: String, Codable, CaseIterable, Identifiable {
    case production
    case staging
    case local

    var id: String { rawValue }

    var label: String {
        switch self {
        case .production: return "Production"
        case .staging: return "Staging"
        case .local: return "Local"
        }
    }

    var defaultWebBaseURL: String {
        switch self {
        case .production: return "https://app.snaptrade.com"
        case .staging: return "https://staging.snaptrade.com"
        case .local: return "http://127.0.0.1:3000"
        }
    }

    var defaultAuthorizationEndpoint: String {
        switch self {
        case .production: return "https://dashboard.snaptrade.com/oauth/authorize"
        case .staging: return "https://dashboard.staging.snaptrade.com/oauth/authorize"
        case .local: return "http://127.0.0.1:8888/oauth/authorize"
        }
    }

    var defaultTokenEndpoint: String {
        switch self {
        case .production: return "https://api.snaptrade.com/oauth/token/"
        case .staging: return "https://api.staging.snaptrade.com/oauth/token/"
        case .local: return "http://127.0.0.1:8888/oauth/token"
        }
    }

    var defaultRevokeEndpoint: String {
        switch self {
        case .production: return "https://api.snaptrade.com/oauth/revoke_token/"
        case .staging: return "https://api.staging.snaptrade.com/oauth/revoke_token/"
        case .local: return "http://127.0.0.1:8888/oauth/revoke"
        }
    }

    var defaultMetadataEndpoint: String {
        switch self {
        case .production: return "https://api.snaptrade.com/.well-known/oauth-authorization-server/mcp"
        case .staging: return "https://api.staging.snaptrade.com/.well-known/oauth-authorization-server/mcp"
        case .local: return "http://127.0.0.1:8888/.well-known/oauth-authorization-server/mcp"
        }
    }

    var defaultOAuthIssuer: String {
        switch self {
        case .production: return "https://api.snaptrade.com"
        case .staging: return "https://api.staging.snaptrade.com"
        case .local: return "http://127.0.0.1:8888"
        }
    }

    var defaultRegistrationEndpoint: String {
        switch self {
        case .production: return "https://api.snaptrade.com/oauth/register/"
        case .staging: return "https://api.staging.snaptrade.com/oauth/register/"
        case .local: return "http://127.0.0.1:8888/oauth/register"
        }
    }

    var defaultAPIBaseURL: String {
        switch self {
        case .production: return "https://api.snaptrade.com/api/v1"
        case .staging: return "https://api.staging.snaptrade.com/api/v1"
        case .local: return "http://127.0.0.1:8888/api/v1"
        }
    }
}

enum RedirectMode: String, Codable, CaseIterable, Identifiable {
    case dynamicLoopback
    case fixed18787

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dynamicLoopback: return "Dynamic loopback"
        case .fixed18787: return "Fixed 127.0.0.1:18787"
        }
    }

    var fixedPort: UInt16? {
        switch self {
        case .dynamicLoopback: return nil
        case .fixed18787: return 18787
        }
    }
}

enum RefreshInterval: String, Codable, CaseIterable, Identifiable {
    case fiveMinutes
    case fifteenMinutes
    case thirtyMinutes
    case oneHour

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        case .oneHour: return "1 hour"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        case .oneHour: return 3600
        }
    }
}
