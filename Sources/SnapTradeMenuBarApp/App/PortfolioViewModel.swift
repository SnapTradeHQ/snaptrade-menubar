import Foundation
import AppKit
import SwiftUI

@MainActor
final class PortfolioViewModel: ObservableObject {
    private static let startupRefreshDebounce: TimeInterval = 5 * 60

    enum ViewState: Equatable {
        case disconnected
        case loading(String)
        case connected(PortfolioSnapshot)
        case stale(PortfolioSnapshot, String)
        case reconnectNeeded(String)
        case error(String)
    }

    @Published private(set) var state: ViewState = .disconnected
    @Published private(set) var isRefreshing = false
    @Published private(set) var syncProgress: PortfolioSyncProgress?

    private let config: AppConfig
    private var tokenStore: TokenStore
    private var authProvider: OAuthProvider
    private var client: SnapTradeClient
    private var aggregator: PortfolioAggregator
    private var snapshotCache: PortfolioSnapshotCache
    private var scheduler: Scheduler?
    private var currentTokenSet: TokenSet?
    private var hasStarted = false

    init() {
        let config = AppConfig.load()
        self.config = config
        self.tokenStore = Self.makeTokenStore(config: config)
        let provider = AuthorizationCodePKCEProvider(config: config)
        self.authProvider = provider
        self.client = SnapTradeClient(config: config)
        self.aggregator = PortfolioAggregator(client: client)
        self.snapshotCache = Self.makeSnapshotCache(config: config)
    }

    var menuBarTitle: String {
        switch state {
        case .connected(let snapshot), .stale(let snapshot, _):
            return NumberFormatters.compactCurrency.string(from: snapshot.totalValue as NSDecimalNumber) ?? "$--"
        case .loading:
            return "Loading"
        case .reconnectNeeded:
            return "Reconnect"
        case .error:
            return "Error"
        case .disconnected:
            return "SnapTrade"
        }
    }

    var menuBarSystemImage: String {
        switch state {
        case .connected:
            return "dollarsign.circle"
        case .stale, .error, .reconnectNeeded:
            return "exclamationmark.triangle"
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .disconnected:
            return "dollarsign.circle"
        }
    }

    var menuContentID: String {
        switch state {
        case .disconnected:
            return "disconnected"
        case .loading:
            return "loading"
        case .connected:
            return "connected"
        case .stale:
            return "stale"
        case .reconnectNeeded:
            return "reconnect-needed"
        case .error:
            return "error"
        }
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await loadStoredSession()
        startScheduler()
    }

    func connect() async {
        state = .loading("Opening SnapTrade...")
        do {
            let tokenSet = try await authProvider.authorize()
            try tokenStore.save(tokenSet)
            currentTokenSet = tokenSet
            await refreshPortfolio(forceTokenRefresh: false)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func refreshNow() async {
        await refreshPortfolio(forceTokenRefresh: false)
    }

    func reconnect() async {
        try? tokenStore.delete()
        currentTokenSet = nil
        await connect()
    }

    func disconnect() async {
        if let tokenSet = currentTokenSet {
            try? await authProvider.revoke(tokenSet)
        }
        try? tokenStore.delete()
        snapshotCache.delete()
        currentTokenSet = nil
        state = .disconnected
    }

    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            state = .error("Could not relaunch the app: \(error.localizedDescription)")
        }
    }

    private func loadStoredSession() async {
        do {
            guard let tokenSet = try tokenStore.load() else {
                state = .disconnected
                return
            }
            currentTokenSet = tokenSet
            if let cachedSnapshot = snapshotCache.load() {
                state = .connected(cachedSnapshot)
                guard shouldRefreshOnStartup(cachedSnapshot) else {
                    return
                }
                Task {
                    await refreshPortfolio(forceTokenRefresh: tokenSet.requiresRefresh)
                }
                return
            }
            await refreshPortfolio(forceTokenRefresh: tokenSet.requiresRefresh)
        } catch {
            state = .error("Could not read Keychain token.")
        }
    }

    private func shouldRefreshOnStartup(_ snapshot: PortfolioSnapshot, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.updatedAt) >= Self.startupRefreshDebounce
    }

    private func refreshPortfolio(forceTokenRefresh: Bool) async {
        guard var tokenSet = currentTokenSet else {
            state = .disconnected
            return
        }

        let previousSnapshot = currentSnapshot
        isRefreshing = true
        syncProgress = .loadingAccounts
        defer {
            isRefreshing = false
            syncProgress = nil
        }

        if previousSnapshot == nil {
            state = .loading("Refreshing portfolio...")
        }

        do {
            if forceTokenRefresh || tokenSet.requiresRefresh {
                tokenSet = try await authProvider.refresh(tokenSet)
                try tokenStore.save(tokenSet)
                currentTokenSet = tokenSet
            }

            do {
                let snapshot = try await fetchSnapshot(accessToken: tokenSet.accessToken)
                snapshotCache.save(snapshot)
                state = .connected(snapshot)
            } catch SnapTradeClientError.unauthorized {
                tokenSet = try await authProvider.refresh(tokenSet)
                try tokenStore.save(tokenSet)
                currentTokenSet = tokenSet
                let snapshot = try await fetchSnapshot(accessToken: tokenSet.accessToken)
                snapshotCache.save(snapshot)
                state = .connected(snapshot)
            }
        } catch let error as OAuthRefreshError {
            state = .reconnectNeeded(error.localizedDescription)
        } catch {
            if let previousSnapshot {
                state = .stale(previousSnapshot, error.localizedDescription)
            } else {
                state = .error(error.localizedDescription)
            }
        }
    }

    private var currentSnapshot: PortfolioSnapshot? {
        switch state {
        case .connected(let snapshot), .stale(let snapshot, _):
            return snapshot
        default:
            return nil
        }
    }

    private func fetchSnapshot(accessToken: String) async throws -> PortfolioSnapshot {
        try await aggregator.fetchPortfolio(accessToken: accessToken) { [weak self] progress in
            self?.syncProgress = progress
        }
    }

    private func startScheduler() {
        scheduler?.cancel()
        scheduler = Scheduler(interval: config.refreshInterval.seconds) { [weak self] in
            Task { @MainActor in
                await self?.refreshPortfolio(forceTokenRefresh: false)
            }
        }
        scheduler?.start()
    }

    private static func makeTokenStore(config: AppConfig) -> TokenStore {
        #if DEBUG
        return UserDefaultsTokenStore(key: "SnapTradeMenuBar.DebugTokenSet.\(config.environment.rawValue)")
        #else
        return KeychainTokenStore(service: "com.snaptrade.menubar.tokens", account: config.environment.rawValue)
        #endif
    }

    private static func makeSnapshotCache(config: AppConfig) -> PortfolioSnapshotCache {
        PortfolioSnapshotCache(key: "SnapTradeMenuBar.PortfolioSnapshot.v3.\(config.environment.rawValue)")
    }

}

private enum NumberFormatters {
    static let compactCurrency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = true
        formatter.formattingContext = .standalone
        return formatter
    }()
}
