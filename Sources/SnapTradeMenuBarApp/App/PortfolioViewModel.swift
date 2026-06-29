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
        case waitingForDeviceApproval(DeviceAuthorizationDisplay)
        case error(String)
    }

    @Published private(set) var state: ViewState = .disconnected
    @Published private(set) var isRefreshing = false
    @Published var config: AppConfig {
        didSet {
            config.save()
            rebuildServices()
        }
    }

    private var tokenStore: TokenStore
    private var authProvider: OAuthProvider
    private var client: SnapTradeClient
    private var aggregator: PortfolioAggregator
    private var snapshotCache: PortfolioSnapshotCache
    private var scheduler: Scheduler?
    private var settingsWindow: NSWindow?
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
        self.authProvider = makeOAuthProvider(config: config)
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
        case .waitingForDeviceApproval:
            return "Approve"
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
        case .loading, .waitingForDeviceApproval:
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
        case .waitingForDeviceApproval:
            return "waiting-for-device-approval"
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
        } catch let error as DeviceAuthorizationPendingError {
            state = .waitingForDeviceApproval(error.display)
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

    func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapTrade Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(viewModel: self))
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
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
        defer { isRefreshing = false }

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
                let snapshot = try await aggregator.fetchPortfolio(accessToken: tokenSet.accessToken)
                snapshotCache.save(snapshot)
                state = .connected(snapshot)
            } catch SnapTradeClientError.unauthorized {
                tokenSet = try await authProvider.refresh(tokenSet)
                try tokenStore.save(tokenSet)
                currentTokenSet = tokenSet
                let snapshot = try await aggregator.fetchPortfolio(accessToken: tokenSet.accessToken)
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

    private func startScheduler() {
        scheduler?.cancel()
        scheduler = Scheduler(interval: config.refreshInterval.seconds) { [weak self] in
            Task { @MainActor in
                await self?.refreshPortfolio(forceTokenRefresh: false)
            }
        }
        scheduler?.start()
    }

    private func rebuildServices() {
        tokenStore = Self.makeTokenStore(config: config)
        authProvider = makeOAuthProvider(config: config)
        client = SnapTradeClient(config: config)
        aggregator = PortfolioAggregator(client: client)
        snapshotCache = Self.makeSnapshotCache(config: config)
        startScheduler()
    }

    private static func makeTokenStore(config: AppConfig) -> TokenStore {
        #if DEBUG
        return UserDefaultsTokenStore(key: "SnapTradeMenuBar.DebugTokenSet.\(config.environment.rawValue)")
        #else
        return KeychainTokenStore(service: "com.snaptrade.menubar.tokens", account: config.environment.rawValue)
        #endif
    }

    private static func makeSnapshotCache(config: AppConfig) -> PortfolioSnapshotCache {
        PortfolioSnapshotCache(key: "SnapTradeMenuBar.PortfolioSnapshot.\(config.environment.rawValue)")
    }

    private func makeOAuthProvider(config: AppConfig) -> OAuthProvider {
        if config.authFlow == .deviceCode {
            return DeviceCodeProvider(config: config) { [weak self] display in
                self?.state = .waitingForDeviceApproval(display)
            }
        }
        return AuthorizationCodePKCEProvider(config: config)
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
