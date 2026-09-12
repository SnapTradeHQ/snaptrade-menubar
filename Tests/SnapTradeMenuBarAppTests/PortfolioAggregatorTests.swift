import Foundation
import Testing
@testable import SnapTradeMenuBarApp

struct PortfolioAggregatorTests {
    @Test(arguments: ["cad", "mixed"]) @MainActor
    func totalsStayInTheirOwnCurrencies(fixture: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var config = AppConfig.defaults
        config.apiBaseURL = "https://\(fixture).fixture/api/v1"
        let aggregator = PortfolioAggregator(client: SnapTradeClient(config: config, session: session),
                                             marketDataProvider: FixtureMarketDataProvider())
        let snapshot = try await aggregator.fetchPortfolio(accessToken: "fixture")
        let expected = fixture == "cad" ? ["CAD"] : ["CAD", "USD"]
        #expect(snapshot.totalsByCurrency.map(\.currency) == expected)
        for total in snapshot.totalsByCurrency {
            #expect(total.brokerReported == 1200)
            #expect(total.calculated == 1200)
        }
        #expect(snapshot.positions.count == expected.count)
        #expect(Set(snapshot.positions.map(\.id)).count == expected.count)
        #expect(snapshot.positions.allSatisfy { $0.value == 1000 && $0.dayChange == 10 })
        if fixture == "cad" {
            #expect(snapshot.currency == "CAD")
            #expect(snapshot.totalValue == 1200)
            #expect(snapshot.dayChange == 10)
            #expect(snapshot.dayChangePercent != nil)
        } else {
            #expect(snapshot.dayChange == nil)
            #expect(snapshot.dayChangePercent == nil)
            #expect(snapshot.positions.allSatisfy { $0.percentOfPortfolio == nil })
        }
        let restored = try JSONDecoder().decode(PortfolioSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored == snapshot)
        if let directory = ProcessInfo.processInfo.environment["SNAPTRADE_FIXTURE_OUTPUT_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(fixture).json")
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        }
    }

    @Test(arguments: ["foreign-holding", "zero-foreign-cash", "foreign-cash", "missing-cash", "missing-total", "unknown-currency", "partial-total", "zero-total"]) @MainActor
    func accountReportingCurrencyControlsTotals(fixture: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var config = AppConfig.defaults
        config.apiBaseURL = "https://\(fixture).fixture/api/v1"
        let snapshot = try await PortfolioAggregator(
            client: SnapTradeClient(config: config, session: session),
            marketDataProvider: FixtureMarketDataProvider()
        ).fetchPortfolio(accessToken: "fixture")
        if fixture == "unknown-currency" {
            #expect(snapshot.visibleCurrencyTotals.map(\.currency) == ["CAD"])
            #expect(snapshot.visibleCurrencyTotals.first?.calculated == 1200)
            #expect(snapshot.visibleCurrencyTotals.first?.brokerReported == nil)
            #expect(snapshot.missingAccountTotalCount == 1)
            #expect(!snapshot.positions.isEmpty)
        } else {
            let foreign = fixture == "foreign-holding" || fixture == "foreign-cash"
            #expect(snapshot.visibleCurrencyTotals.map(\.currency) == (fixture == "zero-total" ? [] : foreign ? ["CAD", "USD"] : ["CAD"]))
            let total = try #require(snapshot.totalsByCurrency.first)
            #expect(total.brokerReported == (fixture == "missing-total" ? nil : fixture == "zero-total" ? 0 : 1200))
            switch fixture {
            case "zero-total":
                #expect(total.calculated == 0)
                #expect(snapshot.visibleCurrencyTotals.isEmpty)
            case "missing-total":
                #expect(total.calculated == 1200)
                #expect(snapshot.visibleCurrencyTotals.count == 1)
                #expect(snapshot.missingAccountTotalCount == 1)
            case "zero-foreign-cash":
                #expect(total.calculated == 1200)
                #expect(total.comparisonUnavailableReason == nil)
                #expect(snapshot.dayChange != nil)
            case "partial-total":
                #expect(total.calculated == 2400)
                #expect(total.missingAccountCount == 1)
                #expect(snapshot.missingAccountTotalCount == 1)
                #expect(snapshot.positions.allSatisfy { $0.percentOfPortfolio == nil })
            case "missing-cash":
                #expect(total.calculated == nil)
                #expect(total.comparisonUnavailableReason == "Cash balances could not be loaded.")
            default:
                #expect(total.calculated == (fixture == "foreign-holding" ? 200 : 1200))
                #expect(total.comparisonUnavailableReason == nil)
                let usd = try #require(snapshot.visibleCurrencyTotals.first { $0.currency == "USD" })
                #expect(usd.brokerReported == nil)
                #expect(usd.calculated == (fixture == "foreign-holding" ? 1000 : 50))
                #expect(snapshot.dayChange == nil)
                if fixture == "foreign-holding" {
                    #expect(snapshot.positions.first?.currency == "USD")
                }
            }
        }
        let restored = try JSONDecoder().decode(PortfolioSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored == snapshot)
        if let directory = ProcessInfo.processInfo.environment["SNAPTRADE_FIXTURE_OUTPUT_DIR"] {
            try JSONEncoder().encode(snapshot).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(fixture).json"))
        }
    }

    @Test @MainActor
    func mixedAssetsInBothReportingCurrencies() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var config = AppConfig.defaults
        config.apiBaseURL = "https://mixed-assets.fixture/api/v1"
        var partials: [PortfolioSnapshot] = []
        var counts: [Int] = []
        let snapshot = try await PortfolioAggregator(
            client: SnapTradeClient(config: config, session: session),
            marketDataProvider: FixtureMarketDataProvider()
        ).fetchPortfolio(accessToken: "fixture", partial: { snapshot, completed, total in
            partials.append(snapshot)
            counts.append(completed)
            #expect(total == 2)
        })
        #expect(counts == [1, 2])
        #expect(partials.first?.accounts.count == 1)
        #expect(partials.last?.accounts.count == 2)
        #expect(partials.allSatisfy { $0.dayChangePercent == nil && $0.positions.allSatisfy { $0.percentOfPortfolio == nil } })
        #expect(partials.first?.positions.count == 2)
        #expect(snapshot.visibleCurrencyTotals.map(\.currency) == ["CAD", "USD"])
        #expect(snapshot.visibleCurrencyTotals.map(\.brokerReported) == [2550, 1800])
        #expect(snapshot.visibleCurrencyTotals.map(\.calculated) == [1800, 2300])
        #expect(snapshot.positions.count == 2)
        #expect(snapshot.positions.allSatisfy { $0.accountCount == 2 })
        #expect(snapshot.positions.first { $0.currency == "CAD" }?.value == 1500)
        #expect(snapshot.positions.first { $0.currency == "USD" }?.value == 2000)
        #expect(snapshot.dayChange == nil)
        if let directory = ProcessInfo.processInfo.environment["SNAPTRADE_FIXTURE_OUTPUT_DIR"] {
            try JSONEncoder().encode(snapshot).write(to: URL(fileURLWithPath: directory).appendingPathComponent("mixed-assets.json"))
        }
    }

    @Test @MainActor
    func mismatchedQuoteCannotRelabelCADValueAsUSD() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var config = AppConfig.defaults
        config.apiBaseURL = "https://cad.fixture/api/v1"
        let aggregator = PortfolioAggregator(client: SnapTradeClient(config: config, session: session),
                                             marketDataProvider: FixtureMarketDataProvider(mismatchedCurrency: true))
        let snapshot = try await aggregator.fetchPortfolio(accessToken: "fixture")
        #expect(snapshot.positions.first?.currency == "CAD")
        #expect(snapshot.positions.first?.value == 1000)
        #expect(snapshot.positions.first?.price == nil)
        #expect(snapshot.dayChange == nil)
    }

    @Test @MainActor
    func discoversAccountsBeforeFetchingTheirCurrentTotals() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PortfolioFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let aggregator = PortfolioAggregator(
            client: SnapTradeClient(config: .defaults, session: session),
            marketDataProvider: EmptyMarketDataProvider()
        )
        var progress: [PortfolioSyncProgress] = []

        let snapshot = try await aggregator.fetchPortfolio(accessToken: "fixture", progress: {
            progress.append($0)
        })

        // Discovery reports 100; the detail endpoint reports 900.
        #expect(snapshot.totalValue == Decimal(900))
        #expect(snapshot.accounts.first?.value == Decimal(900))
        #expect(snapshot.disabledConnections == 1)
        #expect(progress == [
            .loadingAccounts, .accounts(completed: 0, total: 1),
            .accounts(completed: 1, total: 1), .finalizing,
        ])
    }
}

private final class PortfolioFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body: String
        if let host = request.url?.host, host.hasSuffix(".fixture") {
            do {
                let fixture = String(host.split(separator: ".")[0])
                let url = Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")!
                let responses = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
                guard let response = responses[request.url!.path] else { throw URLError(.unsupportedURL) }
                body = String(decoding: try JSONSerialization.data(withJSONObject: response), as: UTF8.self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
        } else {
        switch request.url!.path {
        case "/api/v1/accounts":
            body = #"[{"id":"account-1","balance":{"total":{"amount":100,"currency":"USD"}}}]"#
        case "/api/v1/authorizations":
            body = #"[{"id":"connection-1","disabled":true}]"#
        case "/api/v1/accounts/account-1":
            body = #"{"id":"account-1","balance":{"total":{"amount":900,"currency":"USD"}}}"#
        case "/api/v1/accounts/account-1/positions/all":
            body = #"{"results":[],"data_freshness":{"as_of":null}}"#
        case "/api/v1/accounts/account-1/balances":
            body = #"[{"cash":900,"currency":"USD"}]"#
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private struct EmptyMarketDataProvider: MarketDataProvider {
    func quotes(symbols: [String]) async throws -> [String: MarketQuote] { [:] }
}

@MainActor
private struct FixtureMarketDataProvider: MarketDataProvider {
    var mismatchedCurrency = false
    func quotes(symbols: [String]) async throws -> [String: MarketQuote] {
        Dictionary(uniqueKeysWithValues: symbols.map { symbol in
            let currency = mismatchedCurrency ? "USD" : String(symbol.suffix(3))
            return (symbol, MarketQuote(symbol: symbol, currency: currency, lastPrice: 100,
                                        dayChange: 1, dayChangePercent: Decimal(1) / 99, marketTime: nil))
        })
    }
}
