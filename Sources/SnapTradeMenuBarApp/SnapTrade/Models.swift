import Foundation

struct PortfolioSnapshot: Codable, Equatable {
    let totalValue: Decimal
    let currency: String
    let accounts: [PortfolioAccount]
    let positions: [PortfolioPosition]
    let dayChange: Decimal?
    let dayChangePercent: Decimal?
    let marketSessionAt: Date?
    let disabledConnections: Int?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case totalValue
        case currency
        case accounts
        case positions
        case dayChange
        case dayChangePercent
        case marketSessionAt
        case disabledConnections
        case updatedAt
    }

    init(
        totalValue: Decimal,
        currency: String,
        accounts: [PortfolioAccount],
        positions: [PortfolioPosition],
        dayChange: Decimal?,
        dayChangePercent: Decimal?,
        marketSessionAt: Date?,
        disabledConnections: Int?,
        updatedAt: Date
    ) {
        self.totalValue = totalValue
        self.currency = currency
        self.accounts = accounts
        self.positions = positions
        self.dayChange = dayChange
        self.dayChangePercent = dayChangePercent
        self.marketSessionAt = marketSessionAt
        self.disabledConnections = disabledConnections
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.totalValue = try container.decode(Decimal.self, forKey: .totalValue)
        self.currency = try container.decode(String.self, forKey: .currency)
        self.accounts = try container.decode([PortfolioAccount].self, forKey: .accounts)
        self.positions = try container.decode([PortfolioPosition].self, forKey: .positions)
        self.dayChange = try container.decodeIfPresent(Decimal.self, forKey: .dayChange)
        self.dayChangePercent = try container.decodeIfPresent(Decimal.self, forKey: .dayChangePercent)
        self.marketSessionAt = try container.decodeIfPresent(Date.self, forKey: .marketSessionAt)
        self.disabledConnections = try container.decodeIfPresent(Int.self, forKey: .disabledConnections)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var formattedTotal: String {
        CurrencyFormatter.format(totalValue, currency: currency)
    }

    var formattedDayChangePercent: String? {
        guard let dayChangePercent else { return nil }
        return PercentFormatter.format(dayChangePercent)
    }
}

struct PortfolioAccount: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let institutionName: String
    let value: Decimal
    let currency: String

    var formattedValue: String {
        CurrencyFormatter.format(value, currency: currency)
    }
}

struct PortfolioPosition: Codable, Identifiable, Equatable {
    let id: String
    let symbol: String
    let displayName: String?
    let value: Decimal
    let currency: String
    let price: Decimal?
    let units: Decimal?
    let accountCount: Int
    let percentOfPortfolio: Decimal?
    let dayChange: Decimal?
    let dayChangePercent: Decimal?

    var formattedValue: String {
        CurrencyFormatter.format(value, currency: currency)
    }

    var formattedPrice: String? {
        guard let price else { return nil }
        return CurrencyFormatter.format(price, currency: currency)
    }

    var formattedPercent: String? {
        guard let percentOfPortfolio else { return nil }
        return PercentFormatter.format(percentOfPortfolio)
    }

    var formattedDayChange: String? {
        guard let dayChange else { return nil }
        return CurrencyFormatter.format(dayChange, currency: currency)
    }

    var formattedDayChangePercent: String? {
        guard let dayChangePercent else { return nil }
        return PercentFormatter.format(dayChangePercent, maximumFractionDigits: 2)
    }
}

enum CurrencyFormatter {
    static func format(_ value: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(currency) \(value)"
    }
}

enum PercentFormatter {
    static func format(_ value: Decimal, maximumFractionDigits: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}

struct SnapTradeAccount: Decodable {
    let id: String
    let name: String?
    let number: String?
    let institutionName: String?
    let balance: MoneyValue?
    let balances: [MoneyValue]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case number
        case institutionName = "institution_name"
        case balance
        case balances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeFlexibleString(forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.number = try container.decodeIfPresent(String.self, forKey: .number)
        self.institutionName = try container.decodeIfPresent(String.self, forKey: .institutionName)
        self.balance = try container.decodeIfPresent(MoneyValue.self, forKey: .balance)
        self.balances = try container.decodeIfPresent([MoneyValue].self, forKey: .balances)
    }
}

struct SnapTradeAuthorization: Decodable {
    let id: String
    let disabled: Bool?
    let isDisabled: Bool?
    let status: String?
    let connectionStatus: String?
    let disabledAt: String?
    let disabledDate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case disabled
        case isDisabled = "is_disabled"
        case isDisabledCamel = "isDisabled"
        case status
        case connectionStatus = "connection_status"
        case connectionStatusCamel = "connectionStatus"
        case disabledAt = "disabled_at"
        case disabledAtCamel = "disabledAt"
        case disabledDate = "disabled_date"
        case disabledDateCamel = "disabledDate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeFlexibleString(forKey: .id)
        self.disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        self.isDisabled = try container.decodeIfPresent(Bool.self, forKey: .isDisabled)
            ?? container.decodeIfPresent(Bool.self, forKey: .isDisabledCamel)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.connectionStatus = try container.decodeIfPresent(String.self, forKey: .connectionStatus)
            ?? container.decodeIfPresent(String.self, forKey: .connectionStatusCamel)
        self.disabledAt = try container.decodeIfPresent(String.self, forKey: .disabledAt)
            ?? container.decodeIfPresent(String.self, forKey: .disabledAtCamel)
        self.disabledDate = try container.decodeIfPresent(String.self, forKey: .disabledDate)
            ?? container.decodeIfPresent(String.self, forKey: .disabledDateCamel)
    }

    var isConnectionDisabled: Bool {
        if disabled == true || isDisabled == true {
            return true
        }

        let statusValue = status ?? connectionStatus
        if let statusValue,
           ["disabled", "inactive", "deleted"].contains(statusValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
            return true
        }

        return disabledAt != nil || disabledDate != nil
    }
}

struct SnapTradePosition: Decodable {
    let instrument: Instrument
    let units: Decimal?
    let price: Decimal?
    let costBasis: Decimal?
    let currency: String?
    let cashEquivalent: Bool?
    let taxLots: [TaxLot]?

    enum CodingKeys: String, CodingKey {
        case instrument
        case units
        case price
        case costBasis = "cost_basis"
        case currency
        case cashEquivalent = "cash_equivalent"
        case taxLots = "tax_lots"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.instrument = try container.decode(Instrument.self, forKey: .instrument)
        self.units = try container.decodeFlexibleDecimalIfPresent(forKey: .units)
        self.price = try container.decodeFlexibleDecimalIfPresent(forKey: .price)
        self.costBasis = try container.decodeFlexibleDecimalIfPresent(forKey: .costBasis)
        self.currency = try container.decodeCurrencyCodeIfPresent(forKey: .currency)
        self.cashEquivalent = try container.decodeIfPresent(Bool.self, forKey: .cashEquivalent)
        self.taxLots = try container.decodeIfPresent([TaxLot].self, forKey: .taxLots)
    }
}

struct Instrument: Decodable {
    let kind: String
    let id: String
    let symbol: String?
    let rawSymbol: String?
    let description: String?
    let currency: String?
    let multiplier: Decimal?
    let underlying: UnderlyingInstrument?
    let underlyingInstrument: UnderlyingInstrument?

    enum CodingKeys: String, CodingKey {
        case kind
        case id
        case symbol
        case rawSymbol = "raw_symbol"
        case description
        case currency
        case multiplier
        case underlying
        case underlyingInstrument = "underlying_instrument"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.id = try container.decodeFlexibleString(forKey: .id)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        self.rawSymbol = try container.decodeIfPresent(String.self, forKey: .rawSymbol)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.currency = try container.decodeCurrencyCodeIfPresent(forKey: .currency)
        self.multiplier = try container.decodeFlexibleDecimalIfPresent(forKey: .multiplier)
        self.underlying = try container.decodeIfPresent(UnderlyingInstrument.self, forKey: .underlying)
        self.underlyingInstrument = try container.decodeIfPresent(UnderlyingInstrument.self, forKey: .underlyingInstrument)
    }
}

struct UnderlyingInstrument: Decodable {
    let id: String?
    let symbol: String?
    let rawSymbol: String?
    let description: String?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case id
        case symbol
        case rawSymbol = "raw_symbol"
        case description
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try? container.decodeFlexibleString(forKey: .id)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        self.rawSymbol = try container.decodeIfPresent(String.self, forKey: .rawSymbol)
        self.description = try container.decodeIfPresent(String.self, forKey: .description)
        self.currency = try container.decodeCurrencyCodeIfPresent(forKey: .currency)
    }
}

struct TaxLot: Decodable {}

struct MoneyValue: Decodable {
    let amount: Decimal?
    let cash: Decimal?
    let value: Decimal?
    let total: Decimal?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case cash
        case value
        case total
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.amount = try container.decodeFlexibleDecimalIfPresent(forKey: .amount)
        self.cash = try container.decodeFlexibleDecimalIfPresent(forKey: .cash)
        self.value = try container.decodeFlexibleDecimalIfPresent(forKey: .value)

        if let nestedTotal = try container.decodeIfPresent(NestedAmount.self, forKey: .total) {
            self.total = nestedTotal.amount
            self.currency = nestedTotal.currency
        } else {
            self.total = try container.decodeFlexibleDecimalIfPresent(forKey: .total)
            self.currency = try container.decodeCurrencyCodeIfPresent(forKey: .currency)
        }
    }
}

private struct NestedAmount: Decodable {
    let amount: Decimal?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.amount = try container.decodeFlexibleDecimalIfPresent(forKey: .amount)
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
}

private struct CurrencyObject: Decodable {
    let code: String?
}

extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let string = try? decode(String.self, forKey: key) {
            return string
        }
        if let int = try? decode(Int.self, forKey: key) {
            return String(int)
        }
        if let double = try? decode(Double.self, forKey: key) {
            return String(double)
        }
        return try decode(String.self, forKey: key)
    }

    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let decimal = try? decode(Decimal.self, forKey: key) {
            return decimal
        }
        if let double = try? decode(Double.self, forKey: key) {
            return Decimal(double)
        }
        if let string = try? decode(String.self, forKey: key) {
            return Decimal(string: string)
        }
        return nil
    }

    func decodeCurrencyCodeIfPresent(forKey key: Key) throws -> String? {
        if let code = try? decode(String.self, forKey: key) {
            return code
        }
        if let object = try? decode(CurrencyObject.self, forKey: key) {
            return object.code
        }
        return nil
    }

}
