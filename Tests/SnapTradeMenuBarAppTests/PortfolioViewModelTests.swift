import Foundation
import Testing
@testable import SnapTradeMenuBarApp

struct PortfolioViewModelTests {
    @Test(arguments: [false, true]) @MainActor
    func progressiveLoadingPreservesCompleteCacheAndSession(hasCache: Bool) async throws {
        let suite = "ProgressiveTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsTokenStore(key: "tokens", defaults: defaults)
        try store.save(TokenSet(accessToken: "valid", refreshToken: "refresh", tokenType: "Bearer", expiresAt: .distantFuture))
        let cache = PortfolioSnapshotCache(key: "snapshot", userDefaults: defaults)
        let snapshot = PortfolioSnapshot(totalValue: 100, calculatedValue: 100, currency: "USD", accounts: [], positions: [], dayChange: nil, dayChangePercent: nil, marketSessionAt: nil, disabledConnections: nil, updatedAt: Date())
        if hasCache { cache.save(snapshot) }
        let fetcher = SuspendedPortfolioFetcher()
        let model = PortfolioViewModel(config: .defaults, tokenStore: store, authProvider: SuspendedRefreshProvider(), snapshotCache: cache, aggregator: fetcher)
        if hasCache { await model.start() }
        let task = Task { if hasCache { await model.refreshNow() } else { await model.start() } }
        while fetcher.continuation == nil { await Task.yield() }
        fetcher.partial?(snapshot, 1, 3)
        #expect(model.partialSnapshot == (hasCache ? nil : snapshot))
        #expect(cache.load() == (hasCache ? snapshot : nil))
        if hasCache { #expect(model.state == .connected(snapshot)) }
        fetcher.continuation?.resume(throwing: URLError(.timedOut))
        await task.value
        #expect(!model.isRefreshing)
        #expect(model.partialSnapshot == (hasCache ? nil : snapshot))
        if hasCache {
            guard case .stale = model.state else { Issue.record("Expected stale complete portfolio"); return }
        } else {
            guard case .error = model.state else { Issue.record("Expected retryable partial failure"); return }
        }
        let retry = Task { await model.refreshNow() }
        fetcher.continuation = nil
        while fetcher.continuation == nil { await Task.yield() }
        fetcher.partial?(snapshot, 2, 3)
        fetcher.continuation?.resume(returning: snapshot)
        await retry.value
        #expect(model.state == .connected(snapshot))
        #expect(model.partialSnapshot == nil)
        #expect(cache.load() == snapshot)
        await model.disconnect()
        fetcher.partial?(snapshot, 3, 3)
        #expect(model.state == .disconnected)
        #expect(model.partialSnapshot == nil)
        #expect(cache.load() == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func disconnectIgnoresLateRefreshAndMatchesFreshLaunch(refreshSucceeds: Bool) async throws {
        let suite = "PortfolioViewModelTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsTokenStore(key: "tokens", defaults: defaults)
        let cache = PortfolioSnapshotCache(key: "snapshot", userDefaults: defaults)
        let provider = SuspendedRefreshProvider()
        let fresh = PortfolioViewModel(config: .defaults, tokenStore: store,
                                       authProvider: provider, snapshotCache: cache)
        await fresh.start()
        #expect(fresh.state == .disconnected)

        try store.save(TokenSet(accessToken: "expired", refreshToken: "refresh",
                                tokenType: "Bearer", expiresAt: .distantPast))
        let model = PortfolioViewModel(config: .defaults, tokenStore: store,
                                       authProvider: provider, snapshotCache: cache)
        let startup = Task { await model.start() }
        while provider.continuation == nil { await Task.yield() }
        await model.disconnect()
        #expect(model.state == fresh.state)
        #expect(!model.isRefreshing)
        #expect(model.syncProgress == nil)
        #expect(try store.load() == nil)

        if refreshSucceeds {
            provider.continuation?.resume(returning: TokenSet(
                accessToken: "new", refreshToken: "new-refresh", tokenType: "Bearer", expiresAt: .distantFuture
            ))
        } else {
            provider.continuation?.resume(throwing: OAuthRefreshError())
        }
        await startup.value
        #expect(model.state == fresh.state)
        #expect(!model.isRefreshing)
        #expect(model.syncProgress == nil)
        #expect(try store.load() == nil)

        let relaunched = PortfolioViewModel(config: .defaults, tokenStore: store,
                                            authProvider: provider, snapshotCache: cache)
        await relaunched.start()
        #expect(relaunched.state == fresh.state)
    }
}

@MainActor
private final class SuspendedRefreshProvider: OAuthProvider {
    var continuation: CheckedContinuation<TokenSet, Error>?
    func authorize() async throws -> TokenSet { throw OAuthRefreshError() }
    func refresh(_ tokenSet: TokenSet) async throws -> TokenSet {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func revoke(_ tokenSet: TokenSet) async throws {}
}

@MainActor
private final class SuspendedPortfolioFetcher: PortfolioFetching {
    var partial: ((PortfolioSnapshot, Int, Int) -> Void)?
    var continuation: CheckedContinuation<PortfolioSnapshot, Error>?
    func fetchPortfolio(accessToken: String, partial: ((PortfolioSnapshot, Int, Int) -> Void)?, progress: ((PortfolioSyncProgress) -> Void)?) async throws -> PortfolioSnapshot {
        self.partial = partial
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
