import Foundation
import Network

final class LoopbackCallbackServer: @unchecked Sendable {
    struct Callback {
        let code: String?
        let state: String?
        let error: String?
    }

    private let path: String
    private let fixedPort: UInt16?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, Error>?
    private var didResume = false

    init(path: String, fixedPort: UInt16?) {
        self.path = path
        self.fixedPort = fixedPort
    }

    func start() async throws -> String {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: fixedPort.map { NWEndpoint.Port(rawValue: $0)! } ?? .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            if let fixedPort, isAddressInUse(error) {
                throw LoopbackServerError.portInUse(fixedPort)
            }
            throw error
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue, port != 0 else {
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: LoopbackServerError.noPort)
                        return
                    }
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: port)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    if let fixedPort = self.fixedPort, isAddressInUse(error) {
                        continuation.resume(throwing: LoopbackServerError.portInUse(fixedPort))
                        return
                    }
                    continuation.resume(throwing: error)
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: LoopbackServerError.cancelled)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }

        return "http://127.0.0.1:\(port)\(path)"
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else { return }
            if let error {
                self.finish(with: .failure(error))
                return
            }
            guard let data, let request = String(data: data, encoding: .utf8) else {
                self.finish(with: .failure(LoopbackServerError.invalidRequest))
                return
            }

            let callback = self.parse(request: request)
            self.respond(connection: connection, success: callback.code != nil)
            self.finish(with: .success(callback))
        }
    }

    private func parse(request: String) -> Callback {
        guard let firstLine = request.split(separator: "\r\n").first else {
            return Callback(code: nil, state: nil, error: "Invalid callback request.")
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2,
              let url = URL(string: "http://127.0.0.1\(parts[1])"),
              url.path == path,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return Callback(code: nil, state: nil, error: "Unexpected callback URL.")
        }
        let items = components.queryItems ?? []
        return Callback(
            code: items.first(named: "code")?.value,
            state: items.first(named: "state")?.value,
            error: items.first(named: "error_description")?.value ?? items.first(named: "error")?.value
        )
    }

    private func respond(connection: NWConnection, success: Bool) {
        let title = success ? "SnapTrade connected" : "SnapTrade authorization failed"
        let body = """
        <!doctype html><html><body><h1>\(title)</h1><p>You can close this window and return to the menu bar app.</p></body></html>
        """
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(with result: Result<Callback, Error>) {
        guard !didResume else { return }
        didResume = true
        listener?.cancel()
        switch result {
        case .success(let callback):
            continuation?.resume(returning: callback)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

enum LoopbackServerError: LocalizedError {
    case noPort
    case invalidRequest
    case cancelled
    case portInUse(UInt16)

    var errorDescription: String? {
        switch self {
        case .noPort:
            return "Could not bind loopback callback port."
        case .invalidRequest:
            return "OAuth callback request was invalid."
        case .cancelled:
            return "OAuth callback server was cancelled."
        case .portInUse(let port):
            return "OAuth callback port \(port) is already in use. Stop the local service using that port, or register a different fixed localhost redirect URI in SnapTrade and update the app."
        }
    }
}

private func isAddressInUse(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == EADDRINUSE {
        return true
    }
    let description = String(describing: error)
    return description.contains("error 48") || description.localizedCaseInsensitiveContains("address already in use")
}

private extension Array where Element == URLQueryItem {
    func first(named name: String) -> URLQueryItem? {
        first { $0.name == name }
    }
}
