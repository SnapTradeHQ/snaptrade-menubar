import Foundation
import Testing
@testable import SnapTradeMenuBarApp

struct ModelsTests {
    @Test
    func missingCADPriceDoesNotBlockCompleteUSDSubtotal() throws {
        let positions = try JSONDecoder().decode([SnapTradePosition].self, from: Data(#"[{"instrument":{"kind":"equity","id":"cad","symbol":"CAD","currency":"CAD"},"units":2,"currency":"CAD"},{"instrument":{"kind":"equity","id":"usd","symbol":"USD","currency":"USD"},"units":3,"price":100,"currency":"USD"}]"#.utf8))
        let balances = try JSONDecoder().decode([MoneyValue].self, from: Data(#"[{"cash":50,"currency":"USD"}]"#.utf8))
        let inputs = [AccountValuationInput(positions: positions, balances: balances, accountCurrency: "CAD")]
        #expect(PortfolioValueCalculator.total(accounts: inputs, currency: "CAD") == nil)
        #expect(PortfolioValueCalculator.total(accounts: inputs, currency: "USD") == 350)
    }

    @Test
    func currencyVisibilityRequiresEitherNonzeroValue() {
        let cases: [(Decimal?, Decimal?, Bool)] = [
            (nil, nil, false), (0, nil, false), (nil, 0, false), (0, 0, false),
            (100, nil, true), (nil, 100, true), (100, 0, true), (0, 100, true),
            (-100, 0, true), (0, -100, true), (100, -100, true)
        ]
        for (reported, calculated, visible) in cases {
            let total = PortfolioCurrencyTotal(currency: "CAD", brokerReported: reported, calculated: calculated)
            #expect(total.hasNonzeroValue == visible)
        }
    }

    @Test
    func calculatesCADPositionsAndCashInTheirNativeCurrency() throws {
        let url = Bundle.module.url(forResource: "cad", withExtension: "json", subdirectory: "Fixtures")!
        let responses = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let positionsResponse = responses["/api/v1/accounts/fixture-cad/positions/all"] as! [String: Any]
        let positions = try JSONDecoder().decode([SnapTradePosition].self, from:
            JSONSerialization.data(withJSONObject: positionsResponse["results"]!))
        let balances = try JSONDecoder().decode([MoneyValue].self, from:
            JSONSerialization.data(withJSONObject: responses["/api/v1/accounts/fixture-cad/balances"]!))
        let inputs = [AccountValuationInput(positions: positions, balances: balances)]
        #expect(PortfolioValueCalculator.total(accounts: inputs, currency: "CAD") == 1200)
        #expect(PortfolioValueCalculator.total(accounts: inputs, currency: "USD") == 0)
    }

    @Test
    func authorizationDecodesIDAndDisabledState() throws {
        let data = Data(#"{"id":"connection-123","disabled":true}"#.utf8)

        let authorization = try JSONDecoder().decode(SnapTradeAuthorization.self, from: data)

        #expect(authorization.id == "connection-123")
        #expect(authorization.isConnectionDisabled)
    }

    @Test
    func connectionAccountDecodesBrokerageReportedTotal() throws {
        let data = Data(
            #"{"id":"account-123","name":"Brokerage","institution_name":"Example","balance":{"total":{"amount":1234.56,"currency":"USD"}}}"#.utf8
        )

        let account = try JSONDecoder().decode(SnapTradeAccount.self, from: data)

        #expect(account.id == "account-123")
        #expect(account.balance?.total == Decimal(string: "1234.56"))
        #expect(account.balance?.currency == "USD")
    }

    @Test
    func calculatedValueSumsPositionsAndCashWithoutDoubleCountingCashEquivalents() throws {
        let positionsData = Data(
            #"""
            [
                {"instrument":{"kind":"equity","id":"stock","symbol":"TEST","currency":"USD"},"units":10,"price":50,"currency":"USD","cash_equivalent":false},
                {"instrument":{"kind":"option","id":"option","symbol":"TEST260101C00050000","currency":"USD","multiplier":100},"units":2,"price":3,"currency":"USD","cash_equivalent":false},
                {"instrument":{"kind":"currency","id":"cash","symbol":"USD","currency":"USD"},"units":999,"price":1,"currency":"USD","cash_equivalent":true}
            ]
            """#.utf8
        )
        let balancesData = Data(
            #"[{"currency":{"code":"USD","name":"US Dollar"},"cash":100,"buying_power":500}]"#.utf8
        )
        let positions = try JSONDecoder().decode([SnapTradePosition].self, from: positionsData)
        let balances = try JSONDecoder().decode([MoneyValue].self, from: balancesData)

        let total = PortfolioValueCalculator.total(
            accounts: [AccountValuationInput(positions: positions, balances: balances)],
            currency: "USD"
        )

        #expect(total == Decimal(1_200))
    }

    @Test
    func calculatedValueIsUnavailableWhenPositionPricingIsIncomplete() throws {
        let positionsData = Data(
            #"[{"instrument":{"kind":"equity","id":"stock","symbol":"TEST","currency":"USD"},"units":10,"currency":"USD","cash_equivalent":false}]"#.utf8
        )
        let balancesData = Data(#"[{"currency":{"code":"USD"},"cash":100}]"#.utf8)
        let positions = try JSONDecoder().decode([SnapTradePosition].self, from: positionsData)
        let balances = try JSONDecoder().decode([MoneyValue].self, from: balancesData)

        let total = PortfolioValueCalculator.total(
            accounts: [AccountValuationInput(positions: positions, balances: balances)],
            currency: "USD"
        )

        #expect(total == nil)
    }

    @Test
    func portfolioSnapshotDecodesWithoutCalculatedValueFromOlderCache() throws {
        let data = Data(
            #"{"totalValue":1234.56,"currency":"USD","accounts":[],"positions":[],"updatedAt":0}"#.utf8
        )

        let snapshot = try JSONDecoder().decode(PortfolioSnapshot.self, from: data)

        #expect(snapshot.calculatedValue == nil)
    }
}
