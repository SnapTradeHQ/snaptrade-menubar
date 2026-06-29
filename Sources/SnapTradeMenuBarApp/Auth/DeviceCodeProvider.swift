import AppKit
import Foundation

final class DeviceCodeProvider: OAuthProvider {
    private let config: AppConfig
    private let session: URLSession
    private let metadataClient: OAuthMetadataClient
    private let onDeviceAuthorization: ((DeviceAuthorizationDisplay) -> Void)?

    init(
        config: AppConfig,
        session: URLSession = .shared,
        onDeviceAuthorization: ((DeviceAuthorizationDisplay) -> Void)? = nil
    ) {
        self.config = config
        self.session = session
        self.metadataClient = OAuthMetadataClient(config: config, session: session)
        self.onDeviceAuthorization = onDeviceAuthorization
    }

    func authorize() async throws -> TokenSet {
        guard !config.clientID.isEmpty else {
            throw OAuthProviderError.missingClientID
        }

        let metadata = try await metadataClient.resolve()
        guard metadata.grantTypesSupported.contains(OAuthGrantTypes.deviceCode),
              let endpoint = metadata.deviceAuthorizationEndpoint,
              let deviceAuthorizationURL = URL(string: endpoint) else {
            throw DeviceCodeProviderError.unsupportedServer
        }

        let authorization = try await requestDeviceAuthorization(deviceAuthorizationURL)
        let display = DeviceAuthorizationDisplay(
            userCode: authorization.userCode,
            verificationURI: authorization.verificationURI,
            expiresAt: Date().addingTimeInterval(TimeInterval(authorization.expiresIn))
        )
        onDeviceAuthorization?(display)

        if let verificationURL = URL(string: authorization.verificationURIComplete ?? authorization.verificationURI) {
            _ = NSWorkspace.shared.open(verificationURL)
        }

        return try await pollForToken(
            deviceCode: authorization.deviceCode,
            tokenEndpoint: metadata.tokenEndpoint,
            interval: authorization.interval,
            expiresIn: authorization.expiresIn
        )
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

    private func requestDeviceAuthorization(_ url: URL) async throws -> DeviceAuthorizationResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "client_id": config.clientID,
            "scope": config.scope
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthProviderError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DeviceCodeProviderError.deviceAuthorizationFailed(http.statusCode)
        }
        return try JSONDecoder().decode(DeviceAuthorizationResponse.self, from: data)
    }

    private func pollForToken(
        deviceCode: String,
        tokenEndpoint: String,
        interval: Int,
        expiresIn: Int
    ) async throws -> TokenSet {
        guard let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthProviderError.invalidEndpoint
        }

        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
        var pollInterval = max(interval, 1)

        while Date() < expiresAt {
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: tokenURL)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formBody([
                "grant_type": OAuthGrantTypes.deviceCode,
                "device_code": deviceCode,
                "client_id": config.clientID
            ])

            do {
                return try await performTokenRequest(request, fallbackRefreshToken: nil)
            } catch let error as DevicePollingError {
                switch error.code {
                case "authorization_pending":
                    continue
                case "slow_down":
                    pollInterval += 5
                    continue
                case "access_denied":
                    throw DeviceCodeProviderError.accessDenied
                case "expired_token":
                    throw DeviceCodeProviderError.expired
                default:
                    throw error
                }
            }
        }

        throw DeviceCodeProviderError.expired
    }

    private func performTokenRequest(_ request: URLRequest, fallbackRefreshToken: String?) async throws -> TokenSet {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthProviderError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let pollingError = try? JSONDecoder().decode(DevicePollingError.self, from: data) {
                throw pollingError
            }
            throw OAuthProviderError.tokenExchangeFailed(http.statusCode)
        }

        let responseBody = try JSONDecoder().decode(DeviceTokenResponse.self, from: data)
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

private struct DeviceAuthorizationResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String?
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct DeviceTokenResponse: Decodable {
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

private struct DevicePollingError: LocalizedError, Decodable {
    let code: String
    let description: String?

    enum CodingKeys: String, CodingKey {
        case code = "error"
        case description = "error_description"
    }

    var errorDescription: String? {
        description ?? code
    }
}

enum DeviceCodeProviderError: LocalizedError {
    case unsupportedServer
    case deviceAuthorizationFailed(Int)
    case accessDenied
    case expired

    var errorDescription: String? {
        switch self {
        case .unsupportedServer:
            return "SnapTrade OAuth metadata does not advertise device-code support."
        case .deviceAuthorizationFailed(let status):
            return "Device authorization failed with HTTP \(status)."
        case .accessDenied:
            return "SnapTrade approval was denied."
        case .expired:
            return "SnapTrade approval code expired."
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
