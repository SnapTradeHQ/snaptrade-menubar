import Foundation

struct AppConfig: Codable, Equatable {
    var environment: SnapTradeEnvironment
    var clientID: String
    var authFlow: AuthFlow
    var redirectMode: RedirectMode
    var refreshInterval: RefreshInterval
    var scope: String
    var authorizationEndpoint: String
    var tokenEndpoint: String
    var revokeEndpoint: String
    var metadataEndpoint: String
    var apiBaseURL: String

    static func load() -> AppConfig {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config.withDefaultDemoValues().withEnvironmentOverrides()
        }
        return AppConfig.defaults.withDefaultDemoValues().withEnvironmentOverrides()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
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

    private func withEnvironmentOverrides() -> AppConfig {
        var copy = self
        let env = ProcessInfo.processInfo.environment
        copy.clientID = env["SNAPTRADE_CLIENT_ID"] ?? clientID
        copy.authorizationEndpoint = env["SNAPTRADE_AUTHORIZE_URL"] ?? authorizationEndpoint
        copy.tokenEndpoint = env["SNAPTRADE_TOKEN_URL"] ?? tokenEndpoint
        copy.revokeEndpoint = env["SNAPTRADE_REVOKE_URL"] ?? revokeEndpoint
        copy.metadataEndpoint = env["SNAPTRADE_OAUTH_METADATA_URL"] ?? metadataEndpoint
        copy.apiBaseURL = env["SNAPTRADE_API_BASE_URL"] ?? apiBaseURL
        copy.scope = env["SNAPTRADE_SCOPE"] ?? scope
        return copy
    }

    private func withDefaultDemoValues() -> AppConfig {
        var copy = self
        if copy.clientID.isEmpty {
            copy.clientID = Self.defaultClientID
        }
        copy.redirectMode = .fixed18787
        return copy
    }

    var fallbackOAuthMetadata: OAuthAuthorizationServerMetadata {
        OAuthAuthorizationServerMetadata(
            issuer: environment.defaultOAuthIssuer,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            deviceAuthorizationEndpoint: environment.defaultDeviceAuthorizationEndpoint,
            revocationEndpoint: revokeEndpoint.isEmpty ? nil : revokeEndpoint,
            registrationEndpoint: environment.defaultRegistrationEndpoint,
            scopesSupported: ["read"],
            grantTypesSupported: ["authorization_code", "refresh_token", OAuthGrantTypes.deviceCode],
            codeChallengeMethodsSupported: ["S256"],
            tokenEndpointAuthMethodsSupported: ["none"]
        )
    }

    private static let storageKey = "SnapTradeMenuBar.AppConfig.v1"
    private static let defaultClientID = "OqgWgrKIfojI7ZhONa0xe8fRuqMuvKKE7Grn3H5r"

    static let defaults = AppConfig(
        environment: .production,
        clientID: defaultClientID,
        authFlow: .authorizationCodePKCE,
        redirectMode: .fixed18787,
        refreshInterval: .fifteenMinutes,
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

    var defaultDeviceAuthorizationEndpoint: String {
        switch self {
        case .production: return "https://api.snaptrade.com/oauth/device_authorization/"
        case .staging: return "https://api.staging.snaptrade.com/oauth/device_authorization/"
        case .local: return "http://127.0.0.1:8888/oauth/device_authorization/"
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

enum AuthFlow: String, Codable, CaseIterable, Identifiable {
    case authorizationCodePKCE
    case deviceCode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .authorizationCodePKCE: return "Authorization Code + PKCE"
        case .deviceCode: return "Device Code"
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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .thirtyMinutes: return "30 min"
        }
    }

    var seconds: TimeInterval {
        switch self {
        case .fiveMinutes: return 300
        case .fifteenMinutes: return 900
        case .thirtyMinutes: return 1800
        }
    }
}
