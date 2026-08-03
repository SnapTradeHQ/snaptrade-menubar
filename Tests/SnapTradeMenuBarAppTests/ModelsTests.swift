import Foundation
import Testing
@testable import SnapTradeMenuBarApp

struct ModelsTests {
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
}
