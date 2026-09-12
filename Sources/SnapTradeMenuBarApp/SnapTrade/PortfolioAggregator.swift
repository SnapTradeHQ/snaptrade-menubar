import Foundation

enum PortfolioSyncProgress: Equatable {
    case loadingAccounts
    case accounts(completed: Int, total: Int)
    case finalizing
}

@MainActor
protocol PortfolioFetching {
    func fetchPortfolio(accessToken: String, partial: ((PortfolioSnapshot, Int, Int) -> Void)?,
                        progress: ((PortfolioSyncProgress) -> Void)?) async throws -> PortfolioSnapshot
}

@MainActor
final class PortfolioAggregator: PortfolioFetching {
    private let client: SnapTradeClient
    private let marketDataProvider: MarketDataProvider

    init(client: SnapTradeClient, marketDataProvider: MarketDataProvider = YahooFinanceMarketDataProvider()) {
        self.client = client
        self.marketDataProvider = marketDataProvider
    }

    func fetchPortfolio(
        accessToken: String,
        partial: ((PortfolioSnapshot, Int, Int) -> Void)? = nil,
        progress: ((PortfolioSyncProgress) -> Void)? = nil
    ) async throws -> PortfolioSnapshot {
        progress?(.loadingAccounts)
        let accounts = try await client.accounts(accessToken: accessToken)
        progress?(.accounts(completed: 0, total: accounts.count))
        let authorizations = try await client.authorizations(accessToken: accessToken)
        let disabledConnections = authorizations.filter(\.isConnectionDisabled).count
        var portfolioAccounts: [PortfolioAccount] = []
        var rawPositions: [AccountPosition] = []
        var valuationInputs: [AccountValuationInput] = []

        for (index, account) in accounts.enumerated() {
            let detail = try await details(for: account, accessToken: accessToken)
            rawPositions.append(contentsOf: detail.positions.map { AccountPosition(accountID: account.id, position: $0) })
            valuationInputs.append(AccountValuationInput(positions: detail.positions, balances: detail.balances, accountCurrency: detail.value.currency))
            progress?(.accounts(completed: index + 1, total: accounts.count))
            let accountValue = detail.value
            if let amount = accountValue.amount, let currency = accountValue.currency {
                portfolioAccounts.append(
                    PortfolioAccount(
                        id: account.id,
                        displayName: account.name ?? account.number ?? "Account \(account.id)",
                        institutionName: account.institutionName ?? "SnapTrade",
                        value: amount,
                        currency: currency
                    )
                )
            }
            if let partial {
                let snapshot = await makeSnapshot(portfolioAccounts: portfolioAccounts, rawPositions: rawPositions,
                    valuationInputs: valuationInputs, accountCount: index + 1,
                    disabledConnections: disabledConnections, isPartial: true)
                partial(snapshot, index + 1, accounts.count)
            }
        }
        progress?(.finalizing)
        return await makeSnapshot(portfolioAccounts: portfolioAccounts, rawPositions: rawPositions,
            valuationInputs: valuationInputs, accountCount: accounts.count,
            disabledConnections: disabledConnections, isPartial: false)
    }

    private func makeSnapshot(portfolioAccounts: [PortfolioAccount], rawPositions: [AccountPosition],
                              valuationInputs: [AccountValuationInput], accountCount: Int,
                              disabledConnections: Int, isPartial: Bool) async -> PortfolioSnapshot {
        // Account totals use the broker's reporting currency, not holding/cash denominations.
        let currencies = Set(valuationInputs.compactMap(\.accountCurrency)
            + rawPositions.filter { $0.position.cashEquivalent != true }.compactMap { $0.position.currency ?? $0.position.instrument.currency }
            + valuationInputs.flatMap { $0.balances?.compactMap(\.currency) ?? [] }).sorted()
        let totals = currencies.compactMap { currency -> PortfolioCurrencyTotal? in
            let inputs = valuationInputs.filter { $0.accountCurrency == currency }
            let reported = portfolioAccounts.filter { $0.currency == currency }
            let missing = inputs.count - reported.count
            let comparison = PortfolioValueCalculator.assess(accounts: valuationInputs, currency: currency)
            return PortfolioCurrencyTotal(
                currency: currency,
                brokerReported: reported.isEmpty ? nil : reported.map(\.value).reduce(0, +),
                calculated: comparison.total,
                comparisonUnavailableReason: comparison.reason,
                missingAccountCount: missing
            )
        }
        let valuationCurrencies = Set(valuationInputs.compactMap(\.accountCurrency)
            + rawPositions.compactMap { $0.position.bestMarketValue?.currency }
            + valuationInputs.flatMap { $0.balances?.filter { $0.cash != 0 }.compactMap(\.currency) ?? [] })
        // Legacy scalar fields represent the first currency only; mixed-currency UI uses currencyTotals.
        let primary = totals.first
        let displayCurrency = primary?.currency ?? "USD"
        let total = primary?.brokerReported ?? 0
        let calculatedTotal = primary?.calculated
        let aggregatedPortfolio = await aggregatePositions(rawPositions, total: total, singleCurrency: !isPartial && valuationCurrencies.count == 1 && portfolioAccounts.count == accountCount ? displayCurrency : nil, enrich: !isPartial)

        return PortfolioSnapshot(
            totalValue: total,
            calculatedValue: calculatedTotal,
            currency: displayCurrency,
            accounts: portfolioAccounts,
            positions: aggregatedPortfolio.positions,
            dayChange: aggregatedPortfolio.dayChange,
            dayChangePercent: aggregatedPortfolio.dayChangePercent,
            marketSessionAt: aggregatedPortfolio.marketSessionAt,
            disabledConnections: disabledConnections,
            updatedAt: Date(),
            currencyTotals: totals,
            missingAccountTotalCount: accountCount - portfolioAccounts.count
        )
    }

    private func details(for account: SnapTradeAccount, accessToken: String) async throws -> AccountDetails {
        let accountDetail = try await client.accountDetails(accountID: account.id, accessToken: accessToken)
        let positions = try await client.positions(accountID: account.id, accessToken: accessToken)
        let balances = try? await client.balances(accountID: account.id, accessToken: accessToken)

        return AccountDetails(
            value: accountDetail.balanceTotalValue ?? AccountValue(amount: nil, currency: accountDetail.balance?.currency),
            positions: positions,
            balances: balances
        )
    }

    private func aggregatePositions(_ positions: [AccountPosition], total: Decimal, singleCurrency: String?, enrich: Bool = true) async -> AggregatedPortfolio {
        let grouped = Dictionary(grouping: positions.compactMap(AggregatablePosition.init(accountPosition:))) { position in
            position.key
        }

        let allPositions = grouped.values
            .compactMap { positions -> PortfolioPosition? in
                guard let first = positions.first else { return nil }
                let value = positions.map(\.value).reduce(Decimal(0), +)
                guard value != Decimal(0) else { return nil }
                let units = positions.compactMap(\.units).reduce(Decimal(0), +)
                return PortfolioPosition(
                    id: first.key,
                    symbol: first.symbol,
                    displayName: first.displayName,
                    value: value,
                    currency: first.currency,
                    price: nil,
                    units: units == Decimal(0) ? nil : units,
                    accountCount: Set(positions.map(\.accountKey)).count,
                    percentOfPortfolio: total == 0 || first.currency != singleCurrency ? nil : value / total,
                    dayChange: nil,
                    dayChangePercent: nil
                )
            }
            .sorted { lhs, rhs in
                lhs.currency == rhs.currency ? lhs.value.compare(rhs.value) == .orderedDescending : lhs.currency < rhs.currency
            }

        if !enrich {
            return AggregatedPortfolio(
                positions: Set(allPositions.map(\.currency)).sorted().flatMap { currency in
                    Array(allPositions.filter { $0.currency == currency }.prefix(20))
                }, dayChange: nil, dayChangePercent: nil, marketSessionAt: nil)
        }
        let enrichedPortfolio = await enrichWithMarketMovement(allPositions, grouped: grouped)
        let enrichedPositions = enrichedPortfolio.positions
        let dayChange = enrichedPositions.compactMap(\.dayChange).reduce(Decimal(0), +)
        let openValue = enrichedPositions.compactMap { position -> Decimal? in
            guard let dayChange = position.dayChange else { return nil }
            return position.value - dayChange
        }
        .reduce(Decimal(0), +)
        let dayChangePercent = openValue == Decimal(0) ? nil : dayChange / openValue

        return AggregatedPortfolio(
            positions: Set(enrichedPositions.map(\.currency)).sorted().flatMap { currency in
                Array(enrichedPositions.filter { $0.currency == currency }.prefix(20))
            },
            dayChange: singleCurrency != nil && enrichedPositions.contains { $0.dayChange != nil } ? dayChange : nil,
            dayChangePercent: singleCurrency != nil ? dayChangePercent : nil,
            marketSessionAt: enrichedPortfolio.marketSessionAt
        )
    }

    private func enrichWithMarketMovement(
        _ positions: [PortfolioPosition],
        grouped: [String: [AggregatablePosition]]
    ) async -> EnrichedPortfolioPositions {
        let symbols = positions.map(\.symbol)
        let quotes = (try? await marketDataProvider.quotes(symbols: symbols)) ?? [:]

        let enrichedPositions = positions.map { position in
            guard let quote = quotes[position.symbol],
                  quote.currency == position.currency,
                  let groupedPositions = grouped[position.id] else {
                return position
            }

            let dayChange = groupedPositions
                .map { $0.units * $0.multiplier * quote.dayChange }
                .reduce(Decimal(0), +)

            return PortfolioPosition(
                id: position.id,
                symbol: position.symbol,
                displayName: position.displayName,
                value: position.value,
                currency: position.currency,
                price: quote.lastPrice,
                units: position.units,
                accountCount: position.accountCount,
                percentOfPortfolio: position.percentOfPortfolio,
                dayChange: dayChange,
                dayChangePercent: quote.dayChangePercent
            )
        }

        return EnrichedPortfolioPositions(
            positions: enrichedPositions,
            marketSessionAt: quotes.values.compactMap(\.marketTime).max()
        )
    }
}

private struct AccountPosition {
    let accountID: String
    let position: SnapTradePosition
}

private struct AggregatedPortfolio {
    let positions: [PortfolioPosition]
    let dayChange: Decimal?
    let dayChangePercent: Decimal?
    let marketSessionAt: Date?
}

private struct EnrichedPortfolioPositions {
    let positions: [PortfolioPosition]
    let marketSessionAt: Date?
}

private struct AccountDetails {
    let value: AccountValue
    let positions: [SnapTradePosition]
    let balances: [MoneyValue]?
}

struct AccountValuationInput {
    let positions: [SnapTradePosition]
    let balances: [MoneyValue]?
    var accountCurrency: String? = nil
}

enum PortfolioValueCalculator {
    static func total(accounts: [AccountValuationInput], currency: String) -> Decimal? {
        assess(accounts: accounts, currency: currency).total
    }

    static func assess(accounts: [AccountValuationInput], currency: String) -> (total: Decimal?, reason: String?) {
        var total = Decimal(0)
        for account in accounts {
            guard let balances = account.balances else { return (nil, "Cash balances could not be loaded.") }
            for balance in balances {
                if balance.cash == 0 { continue }
                guard let denomination = balance.currency else { return (nil, "Some cash currencies are missing.") }
                guard denomination == currency else { continue }
                guard let cash = balance.cash else { return (nil, "Some cash amounts are missing.") }
                total += cash
            }
            for position in account.positions where position.cashEquivalent != true {
                if position.units == 0 { continue }
                guard let denomination = position.currency ?? position.instrument.currency else {
                    return (nil, "Some holding currencies are missing.")
                }
                guard denomination == currency else { continue }
                guard let amount = position.bestMarketValue?.amount else {
                    return (nil, "Some holding values are missing.")
                }
                total += amount
            }
        }
        return (total, nil)
    }
}

private struct AccountValue {
    let amount: Decimal?
    let currency: String?
}

private struct AggregatablePosition {
    let key: String
    let symbol: String
    let displayName: String?
    let value: Decimal
    let currency: String
    let units: Decimal
    let multiplier: Decimal
    let accountKey: String

    init?(accountPosition: AccountPosition) {
        let position = accountPosition.position
        guard position.cashEquivalent != true,
              let rawSymbol = position.instrument.symbol?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawSymbol.isEmpty,
              let units = position.units,
              let marketValue = position.bestMarketValue?.amount,
              let currency = position.bestMarketValue?.currency else {
            return nil
        }
        let symbol = rawSymbol.uppercased()
        self.key = position.instrument.id + ":" + currency
        self.symbol = symbol
        self.displayName = position.instrument.description
        self.value = marketValue
        self.currency = currency
        self.units = units
        self.multiplier = position.instrument.valueMultiplier
        self.accountKey = accountPosition.accountID
    }
}

private extension SnapTradeAccount {
    var balanceTotalValue: AccountValue? {
        guard let total = balance?.total else { return nil }
        return AccountValue(amount: total, currency: balance?.currency)
    }
}

private extension SnapTradePosition {
    var bestMarketValue: AccountValue? {
        if let units, let price {
            return AccountValue(
                amount: units * price * instrument.valueMultiplier,
                currency: currency ?? instrument.currency
            )
        }
        return nil
    }
}

private extension Instrument {
    var valueMultiplier: Decimal {
        multiplier ?? Decimal(1)
    }
}

private extension Decimal {
    func compare(_ other: Decimal) -> ComparisonResult {
        (self as NSDecimalNumber).compare(other as NSDecimalNumber)
    }
}
