import Foundation

enum OAuthGrantTypes {
    static let deviceCode = "urn:ietf:params:oauth:grant-type:device_code"
}

@MainActor
protocol OAuthProvider {
    func authorize() async throws -> TokenSet
    func refresh(_ tokenSet: TokenSet) async throws -> TokenSet
    func revoke(_ tokenSet: TokenSet) async throws
}

struct TokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var tokenType: String
    var expiresAt: Date?
    var scope: String?

    var requiresRefresh: Bool {
        guard let expiresAt else { return false }
        return expiresAt.timeIntervalSinceNow < 60
    }
}

struct OAuthRefreshError: LocalizedError {
    var errorDescription: String? = "Refresh token is no longer valid."
}

struct DeviceAuthorizationDisplay: Equatable {
    let userCode: String
    let verificationURI: String
    let expiresAt: Date
}

struct DeviceAuthorizationPendingError: Error {
    let display: DeviceAuthorizationDisplay
}
