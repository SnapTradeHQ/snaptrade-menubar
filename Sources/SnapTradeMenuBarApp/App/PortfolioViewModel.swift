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
    @Published private(set) var partialSnapshot: PortfolioSnapshot?
    @Published private(set) var partialAccountCount = 0
    @Published private(set) var totalAccountCount = 0
    @Published private(set) var syncProgress: PortfolioSyncProgress?

    private let config: AppConfig
    private var tokenStore: TokenStore
    private var authProvider: OAuthProvider
    private var client: SnapTradeClient
    private var aggregator: any PortfolioFetching
    private var snapshotCache: PortfolioSnapshotCache
    private var scheduler: Scheduler?
    private var currentTokenSet: TokenSet?
    private var hasStarted = false
    // Ignore results from work started before a disconnect or a new sign-in.
    private var sessionID = UUID()

    var isPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SNAPTRADE_PREVIEW_SNAPSHOT"] != nil
        #else
        return false
        #endif
    }

    init(config: AppConfig = AppConfig.load(), tokenStore: TokenStore? = nil,
         authProvider: OAuthProvider? = nil, snapshotCache: PortfolioSnapshotCache? = nil,
         aggregator: (any PortfolioFetching)? = nil) {
        self.config = config
        self.tokenStore = tokenStore ?? Self.makeTokenStore(config: config)
        let provider = AuthorizationCodePKCEProvider(config: config)
        self.authProvider = authProvider ?? provider
        self.client = SnapTradeClient(config: config)
        self.aggregator = aggregator ?? PortfolioAggregator(client: client)
        self.snapshotCache = snapshotCache ?? Self.makeSnapshotCache(config: config)
    }

    var menuBarTitle: String {
        switch state {
        case .connected(let snapshot), .stale(let snapshot, _):
            guard !snapshot.totalsByCurrency.isEmpty else { return "Account totals unavailable" }
            let amounts = snapshot.totalsByCurrency.map { total in
                total.brokerReported.map { CurrencyFormatter.format($0, currency: total.currency) } ?? "\(total.currency) unavailable"
            }.joined(separator: " · ")
            return amounts + ((snapshot.missingAccountTotalCount ?? 0) > 0 ? " (incomplete)" : "")
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

    var menuBarSystemImage: String? {
        switch state {
        case .stale, .error, .reconnectNeeded:
            return "exclamationmark.triangle"
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .connected, .disconnected:
            return nil
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
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["SNAPTRADE_PREVIEW_SNAPSHOT"] {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                state = .connected(try JSONDecoder().decode(PortfolioSnapshot.self, from: data))
            } catch {
                state = .error("Could not load sample portfolio: \(error.localizedDescription)")
            }
            return
        }
        #endif
        await loadStoredSession()
        startScheduler()
    }

    func connect() async {
        guard !isPreview else { return }
        partialSnapshot = nil
        partialAccountCount = 0
        totalAccountCount = 0
        sessionID = UUID()
        let sessionID = self.sessionID
        isRefreshing = false
        syncProgress = nil
        state = .loading("Opening SnapTrade...")
        do {
            let tokenSet = try await authProvider.authorize()
            guard sessionID == self.sessionID else { return }
            try tokenStore.save(tokenSet)
            currentTokenSet = tokenSet
            await refreshPortfolio(forceTokenRefresh: false)
        } catch {
            guard sessionID == self.sessionID else { return }
            state = .error(error.localizedDescription)
        }
    }

    func refreshNow() async {
        await refreshPortfolio(forceTokenRefresh: false)
    }

    func reconnect() async {
        guard !isPreview else { return }
        try? tokenStore.delete()
        currentTokenSet = nil
        await connect()
    }

    func disconnect() async {
        guard !isPreview else { return }
        let tokenSet = currentTokenSet
        partialSnapshot = nil
        partialAccountCount = 0
        totalAccountCount = 0
        sessionID = UUID()
        try? tokenStore.delete()
        snapshotCache.delete()
        currentTokenSet = nil
        isRefreshing = false
        syncProgress = nil
        state = .disconnected
        if let tokenSet {
            try? await authProvider.revoke(tokenSet)
        }
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
        guard !isRefreshing, var tokenSet = currentTokenSet else {
            return
        }

        let sessionID = self.sessionID
        let previousSnapshot = currentSnapshot
        isRefreshing = true
        syncProgress = .loadingAccounts
        defer {
            if sessionID == self.sessionID {
                isRefreshing = false
                syncProgress = nil
            }
        }

        if previousSnapshot == nil {
            state = .loading("Refreshing portfolio...")
        }

        do {
            if forceTokenRefresh || tokenSet.requiresRefresh {
                tokenSet = try await authProvider.refresh(tokenSet)
                guard sessionID == self.sessionID else { return }
                try tokenStore.save(tokenSet)
                currentTokenSet = tokenSet
            }

            do {
                let snapshot = try await fetchSnapshot(accessToken: tokenSet.accessToken, sessionID: sessionID)
                guard sessionID == self.sessionID else { return }
                partialSnapshot = nil
                snapshotCache.save(snapshot)
                state = .connected(snapshot)
            } catch SnapTradeClientError.unauthorized {
                guard sessionID == self.sessionID else { return }
                tokenSet = try await authProvider.refresh(tokenSet)
                guard sessionID == self.sessionID else { return }
                try tokenStore.save(tokenSet)
                currentTokenSet = tokenSet
                let snapshot = try await fetchSnapshot(accessToken: tokenSet.accessToken, sessionID: sessionID)
                guard sessionID == self.sessionID else { return }
                partialSnapshot = nil
                snapshotCache.save(snapshot)
                state = .connected(snapshot)
            }
        } catch let error as OAuthRefreshError {
            guard sessionID == self.sessionID else { return }
            state = .reconnectNeeded(error.localizedDescription)
        } catch {
            guard sessionID == self.sessionID else { return }
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

    private func fetchSnapshot(accessToken: String, sessionID: UUID) async throws -> PortfolioSnapshot {
        let showPartial = currentSnapshot == nil
        return try await aggregator.fetchPortfolio(accessToken: accessToken, partial: { [weak self] snapshot, completed, total in
            guard let self, sessionID == self.sessionID, showPartial else { return }
            self.partialAccountCount = completed
            self.totalAccountCount = total
            self.partialSnapshot = snapshot
        }, progress: { [weak self] progress in
            guard let self, sessionID == self.sessionID else { return }
            self.syncProgress = progress
        })
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
        return UserDefaultsTokenStore(key: "SnapTradeMenuBar.DebugTokenSet.v2.\(config.sessionStorageID)")
        #else
        return KeychainTokenStore(service: "com.snaptrade.menubar.tokens", account: config.sessionStorageID)
        #endif
    }

    private static func makeSnapshotCache(config: AppConfig) -> PortfolioSnapshotCache {
        PortfolioSnapshotCache(key: "SnapTradeMenuBar.PortfolioSnapshot.v8.\(config.sessionStorageID)")
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
