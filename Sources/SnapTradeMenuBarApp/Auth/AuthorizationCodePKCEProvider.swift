import AppKit
import Foundation

final class AuthorizationCodePKCEProvider: OAuthProvider {
    private let config: AppConfig
    private let session: URLSession
    private let metadataClient: OAuthMetadataClient

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
        self.metadataClient = OAuthMetadataClient(config: config, session: session)
    }

    func authorize() async throws -> TokenSet {
        guard !config.clientID.isEmpty else {
            throw OAuthProviderError.missingClientID
        }

        let pkce = try PKCE.make()
        let state = PKCE.randomURLSafeString(byteCount: 32)
        let metadata = try await metadataClient.resolve()
        let callbackServer = LoopbackCallbackServer(
            path: "/oauth/callback",
            fixedPort: config.redirectMode.fixedPort
        )
        let redirectURI = try await callbackServer.start()
        let authorizeURL = try buildAuthorizeURL(
            endpoint: metadata.authorizationEndpoint,
            redirectURI: redirectURI,
            state: state,
            codeChallenge: pkce.challenge
        )

        await MainActor.run {
            _ = NSWorkspace.shared.open(authorizeURL)
        }

        let callback = try await callbackServer.waitForCallback()
        guard callback.state == state else {
            throw OAuthProviderError.invalidState
        }
        guard let code = callback.code else {
            throw OAuthProviderError.authorizationDenied(callback.error ?? "Missing authorization code.")
        }

        return try await exchangeCode(code, redirectURI: redirectURI, codeVerifier: pkce.verifier, tokenEndpoint: metadata.tokenEndpoint)
    }

    func refresh(_ tokenSet: TokenSet) async throws -> TokenSet {
        guard let refreshToken = tokenSet.refreshToken, !refreshToken.isEmpty else {
            throw OAuthRefreshError()
        }

        let metadata = try await metadataClient.resolve()
        guard let tokenURL = URL(string: metadata.tokenEndpoint) else {
            throw OAuthProviderError.invalidEndpoint
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID
        ])

        do {
            return try await performTokenRequest(request, fallbackRefreshToken: refreshToken)
        } catch {
            throw OAuthRefreshError()
        }
    }

    func revoke(_ tokenSet: TokenSet) async throws {
        let metadata = try await metadataClient.resolve()
        guard let refreshToken = tokenSet.refreshToken,
              let revocationEndpoint = metadata.revocationEndpoint,
              let revokeURL = URL(string: revocationEndpoint) else {
            return
        }

        var request = URLRequest(url: revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "token": refreshToken,
            "client_id": config.clientID
        ])
        _ = try? await session.data(for: request)
    }

    private func buildAuthorizeURL(endpoint: String, redirectURI: String, state: String, codeChallenge: String) throws -> URL {
        guard let endpointURL = URL(string: endpoint) else {
            throw OAuthProviderError.invalidEndpoint
        }
        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = components?.url else {
            throw OAuthProviderError.invalidEndpoint
        }
        return url
    }

    private func exchangeCode(_ code: String, redirectURI: String, codeVerifier: String, tokenEndpoint: String) async throws -> TokenSet {
        guard let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthProviderError.invalidEndpoint
        }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": config.clientID,
            "code_verifier": codeVerifier
        ])
        return try await performTokenRequest(request, fallbackRefreshToken: nil)
    }

    private func performTokenRequest(_ request: URLRequest, fallbackRefreshToken: String?) async throws -> TokenSet {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthProviderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthProviderError.tokenExchangeFailed(http.statusCode)
        }

        let responseBody = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenSet(
            accessToken: responseBody.accessToken,
            refreshToken: responseBody.refreshToken ?? fallbackRefreshToken,
            tokenType: responseBody.tokenType ?? "Bearer",
            expiresAt: responseBody.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            scope: responseBody.scope
        )
    }

    private func formBody(_ values: [String: String]) -> Data {
        values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

enum OAuthProviderError: LocalizedError {
    case missingClientID
    case invalidEndpoint
    case invalidResponse
    case invalidState
    case authorizationDenied(String)
    case tokenExchangeFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "OAuth client ID is required."
        case .invalidEndpoint:
            return "OAuth endpoint is not a valid URL."
        case .invalidResponse:
            return "OAuth server returned an invalid response."
        case .invalidState:
            return "OAuth callback state did not match."
        case .authorizationDenied(let message):
            return message
        case .tokenExchangeFailed(let status):
            return "Token exchange failed with HTTP \(status)."
        }
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=")
        return set
    }()
}
