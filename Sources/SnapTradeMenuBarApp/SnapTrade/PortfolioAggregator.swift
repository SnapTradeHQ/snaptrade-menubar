import Foundation

enum PortfolioSyncProgress: Equatable {
    case loadingAccounts
    case accounts(completed: Int, total: Int)
    case finalizing
}

@MainActor
final class PortfolioAggregator {
    private let client: SnapTradeClient
    private let marketDataProvider: MarketDataProvider
    private let displayCurrency = "USD"

    init(client: SnapTradeClient, marketDataProvider: MarketDataProvider = YahooFinanceMarketDataProvider()) {
        self.client = client
        self.marketDataProvider = marketDataProvider
    }

    func fetchPortfolio(
        accessToken: String,
        progress: ((PortfolioSyncProgress) -> Void)? = nil
    ) async throws -> PortfolioSnapshot {
        progress?(.loadingAccounts)
        let authorizations = try await client.authorizations(accessToken: accessToken)
        var accounts: [SnapTradeAccount] = []
        var seenAccountIDs: Set<String> = []

        for authorization in authorizations {
            let connectionAccounts = try await client.accounts(
                authorizationID: authorization.id,
                accessToken: accessToken
            )
            for account in connectionAccounts where seenAccountIDs.insert(account.id).inserted {
                accounts.append(account)
            }
        }

        progress?(.accounts(completed: 0, total: accounts.count))
        let disabledConnections = authorizations.filter(\.isConnectionDisabled).count
        var portfolioAccounts: [PortfolioAccount] = []
        var rawPositions: [AccountPosition] = []
        var valuationInputs: [AccountValuationInput] = []

        for (index, account) in accounts.enumerated() {
            let detail = try await details(for: account, accessToken: accessToken)
            rawPositions.append(contentsOf: detail.positions.map { AccountPosition(accountID: account.id, position: $0) })
            valuationInputs.append(AccountValuationInput(positions: detail.positions, balances: detail.balances))
            progress?(.accounts(completed: index + 1, total: accounts.count))
            let accountValue = detail.value
            guard let amount = accountValue.amount else { continue }
            portfolioAccounts.append(
                PortfolioAccount(
                    id: account.id,
                    displayName: account.name ?? account.number ?? "Account \(account.id)",
                    institutionName: account.institutionName ?? "SnapTrade",
                    value: amount,
                    currency: accountValue.currency ?? displayCurrency
                )
            )
        }

        let total = portfolioAccounts
            .filter { $0.currency == displayCurrency }
            .map(\.value)
            .reduce(Decimal(0), +)
        let calculatedTotal = PortfolioValueCalculator.total(
            accounts: valuationInputs,
            currency: displayCurrency
        )

        progress?(.finalizing)
        let aggregatedPortfolio = await aggregatePositions(rawPositions, total: total)

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
            updatedAt: Date()
        )
    }

    private func details(for account: SnapTradeAccount, accessToken: String) async throws -> AccountDetails {
        let positions = try await client.positions(accountID: account.id, accessToken: accessToken)
        let balances = try? await client.balances(accountID: account.id, accessToken: accessToken)

        return AccountDetails(
            value: account.balanceTotalValue ?? AccountValue(amount: nil, currency: displayCurrency),
            positions: positions,
            balances: balances
        )
    }

    private func aggregatePositions(_ positions: [AccountPosition], total: Decimal) async -> AggregatedPortfolio {
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
                    percentOfPortfolio: total == Decimal(0) ? nil : value / total,
                    dayChange: nil,
                    dayChangePercent: nil
                )
            }
            .sorted { lhs, rhs in
                lhs.value.compare(rhs.value) == .orderedDescending
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
            positions: Array(enrichedPositions.prefix(20)),
            dayChange: enrichedPositions.contains { $0.dayChange != nil } ? dayChange : nil,
            dayChangePercent: dayChangePercent,
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
                currency: quote.currency ?? position.currency,
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
}

enum PortfolioValueCalculator {
    static func total(accounts: [AccountValuationInput], currency: String) -> Decimal? {
        var total = Decimal(0)

        for account in accounts {
            guard let balances = account.balances else { return nil }

            for balance in balances {
                guard let cash = balance.cash,
                      let balanceCurrency = balance.currency,
                      balanceCurrency == currency else {
                    return nil
                }
                total += cash
            }

            for position in account.positions where position.cashEquivalent != true {
                guard let marketValue = position.bestMarketValue,
                      let amount = marketValue.amount,
                      let positionCurrency = marketValue.currency,
                      positionCurrency == currency else {
                    return nil
                }
                total += amount
            }
        }

        return total
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
              let marketValue = position.bestMarketValue?.amount else {
            return nil
        }
        let symbol = rawSymbol.uppercased()
        self.key = position.instrument.id
        self.symbol = symbol
        self.displayName = position.instrument.description
        self.value = marketValue
        self.currency = position.bestMarketValue?.currency ?? "USD"
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
