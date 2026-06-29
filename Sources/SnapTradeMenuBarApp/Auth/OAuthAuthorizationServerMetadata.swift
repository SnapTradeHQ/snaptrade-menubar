import Foundation

struct OAuthAuthorizationServerMetadata: Decodable, Equatable {
    let issuer: String
    let authorizationEndpoint: String
    let tokenEndpoint: String
    let deviceAuthorizationEndpoint: String?
    let revocationEndpoint: String?
    let registrationEndpoint: String?
    let scopesSupported: [String]
    let grantTypesSupported: [String]
    let codeChallengeMethodsSupported: [String]
    let tokenEndpointAuthMethodsSupported: [String]

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case deviceAuthorizationEndpoint = "device_authorization_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case scopesSupported = "scopes_supported"
        case grantTypesSupported = "grant_types_supported"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
    }
}

@MainActor
final class OAuthMetadataClient {
    private let config: AppConfig
    private let session: URLSession

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func resolve() async throws -> OAuthAuthorizationServerMetadata {
        guard !config.metadataEndpoint.isEmpty, let url = URL(string: config.metadataEndpoint) else {
            return config.fallbackOAuthMetadata
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OAuthMetadataError.discoveryFailed
        }

        let metadata = try JSONDecoder().decode(OAuthAuthorizationServerMetadata.self, from: data)
        guard metadata.grantTypesSupported.contains("authorization_code"),
              metadata.grantTypesSupported.contains("refresh_token"),
              metadata.codeChallengeMethodsSupported.contains("S256") else {
            throw OAuthMetadataError.unsupportedServer
        }
        return metadata
    }
}

enum OAuthMetadataError: LocalizedError {
    case discoveryFailed
    case unsupportedServer

    var errorDescription: String? {
        switch self {
        case .discoveryFailed:
            return "Could not load SnapTrade OAuth metadata."
        case .unsupportedServer:
            return "SnapTrade OAuth metadata does not advertise authorization_code, refresh_token, and PKCE S256 support."
        }
    }
}
