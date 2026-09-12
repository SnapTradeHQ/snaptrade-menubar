import Foundation
import Testing
@testable import SnapTradeMenuBarApp

struct OAuthConfigurationTests {
    @Test func migratesSavedTestClientOnceWithoutChangingPreferences() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var old = AppConfig.defaults
        old.clientID = AppConfig.legacyTestClientID
        old.refreshInterval = .thirtyMinutes
        old.save(defaults: defaults)
        defaults.set("keep", forKey: "unrelated")
        let migrated = AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production")
        #expect(migrated.clientID == "fixture-production")
        #expect(migrated.refreshInterval == .thirtyMinutes)
        #expect(defaults.string(forKey: "unrelated") == "keep")
        #expect(AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production") == migrated)
    }

    @Test func preservesDevelopmentOverridesWithoutPersistingEnvironment() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var config = AppConfig.defaults
        config.clientID = "custom-development-client"
        config.save(defaults: defaults)
        #expect(AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production").clientID == config.clientID)
        let overridden = AppConfig.load(defaults: defaults, environment: ["SNAPTRADE_CLIENT_ID": AppConfig.legacyTestClientID], productionClientID: "fixture-production")
        #expect(overridden.clientID == AppConfig.legacyTestClientID)
        #expect(AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production").clientID == config.clientID)
    }

    @Test func explicitTestOverrideDoesNotUndoPersistedMigration() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var old = AppConfig.defaults
        old.clientID = AppConfig.legacyTestClientID
        old.save(defaults: defaults)
        let override = AppConfig.load(defaults: defaults, environment: ["SNAPTRADE_CLIENT_ID": AppConfig.legacyTestClientID], productionClientID: "fixture-production")
        #expect(override.clientID == AppConfig.legacyTestClientID)
        #expect(AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production").clientID == "fixture-production")
    }

    @Test func clientAndEndpointChangesCannotReuseTokensOrLegacyStorage() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var testConfig = AppConfig.defaults
        testConfig.clientID = AppConfig.legacyTestClientID
        var production = testConfig
        production.clientID = "fixture-production"
        let testStore = UserDefaultsTokenStore(key: testConfig.sessionStorageID, defaults: defaults)
        let productionStore = UserDefaultsTokenStore(key: production.sessionStorageID, defaults: defaults)
        let token = TokenSet(accessToken: "fixture", refreshToken: "fixture-refresh", tokenType: "Bearer", expiresAt: nil, scope: "read")
        try testStore.save(token)
        try UserDefaultsTokenStore(key: "SnapTradeMenuBar.DebugTokenSet.production", defaults: defaults).save(token)
        #expect(try productionStore.load() == nil)
        try productionStore.save(token)
        #expect(try UserDefaultsTokenStore(key: production.sessionStorageID, defaults: defaults).load() == token)
        #expect(try testStore.load() == token)
        var changed = production
        changed.tokenEndpoint = "http://localhost:8888/token"
        #expect(changed.sessionStorageID != production.sessionStorageID)
        changed = production
        changed.apiBaseURL = "http://localhost:8888/api"
        #expect(changed.sessionStorageID != production.sessionStorageID)
    }

    @Test func customPersistedEndpointsAreNotMigrated() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var config = AppConfig.defaults
        config.tokenEndpoint = "http://localhost:8888/token"
        config.save(defaults: defaults)
        let loaded = AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production")
        #expect(loaded.clientID == config.clientID)
        #expect(loaded.tokenEndpoint == config.tokenEndpoint)
    }

    @Test func emptySavedClientUsesVerifiedProductionDefault() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var config = AppConfig.defaults
        config.clientID = ""
        config.save(defaults: defaults)
        #expect(AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production").clientID == "fixture-production")
    }

    @Test func stagingClientIsNotMigrated() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var config = AppConfig.defaults
        config.environment = .staging
        config.save(defaults: defaults)
        #expect(AppConfig.load(defaults: defaults, environment: [:], productionClientID: "fixture-production").clientID == config.clientID)
    }
}

@MainActor
struct OAuthRequestTests {
    @Test func authorizationUsesPKCEAndExactCallbackWithoutSecret() throws {
        var config = AppConfig.defaults
        config.clientID = "fixture-production"
        let provider = AuthorizationCodePKCEProvider(config: config)
        let url = try provider.buildAuthorizeURL(endpoint: config.authorizationEndpoint,
            redirectURI: "http://127.0.0.1:18787/oauth/callback", state: "fixture-state", codeChallenge: "fixture-challenge")
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        #expect(query["client_id"] == config.clientID)
        #expect(query["redirect_uri"] == "http://127.0.0.1:18787/oauth/callback")
        #expect(query["response_type"] == "code")
        #expect(query["state"] == "fixture-state")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == "fixture-challenge")
        #expect(query["client_secret"] == nil)
    }

    @Test func pkceGeneratesUniqueURLSafeValues() throws {
        let first = try PKCE.make()
        let second = try PKCE.make()
        #expect(first.verifier != second.verifier)
        #expect(first.verifier.count >= 43)
        #expect(first.challenge.count == 43)
        #expect(!first.verifier.contains("="))
        #expect(!first.challenge.contains("+"))
        #expect(!first.challenge.contains("/"))
    }
}
