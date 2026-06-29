import Foundation

struct MarketQuote: Equatable {
    let symbol: String
    let currency: String?
    let lastPrice: Decimal
    let openPrice: Decimal
    let marketTime: Date?
}

@MainActor
protocol MarketDataProvider {
    func quotes(symbols: [String]) async throws -> [String: MarketQuote]
}

@MainActor
final class YahooFinanceMarketDataProvider: MarketDataProvider {
    private static let userAgent = "Mozilla/5.0 (compatible; yahoo-finance2/3.14.0)"
    private static let quotePageURL = URL(string: "https://finance.yahoo.com/quote/AAPL")!
    private static let crumbURL = URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb")!

    private let session: URLSession
    private let decoder = JSONDecoder()
    private var crumb: String?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func quotes(symbols: [String]) async throws -> [String: MarketQuote] {
        let originalSymbols = Array(Set(symbols)).sorted()
        guard !originalSymbols.isEmpty else { return [:] }

        var result: [String: MarketQuote] = [:]
        for batch in originalSymbols.chunked(into: 50) {
            let batchQuotes = try await fetchBatch(symbols: batch)
            result.merge(batchQuotes) { current, _ in current }
        }
        return result
    }

    private func fetchBatch(symbols: [String]) async throws -> [String: MarketQuote] {
        let sanitizedPairs = symbols.map { original in
            (original: original, yahoo: Self.yahooSymbol(from: original))
        }
        let yahooSymbols = sanitizedPairs.map(\.yahoo).joined(separator: ",")
        let firstAttempt = try await fetchBatch(symbols: sanitizedPairs, yahooSymbols: yahooSymbols)
        if !firstAttempt.isEmpty {
            return firstAttempt
        }

        crumb = nil
        return try await fetchBatch(symbols: sanitizedPairs, yahooSymbols: yahooSymbols)
    }

    private func fetchBatch(
        symbols sanitizedPairs: [(original: String, yahoo: String)],
        yahooSymbols: String
    ) async throws -> [String: MarketQuote] {
        guard let crumb = try await yahooCrumb() else { return [:] }

        var components = URLComponents(string: "https://query2.finance.yahoo.com/v7/finance/quote")
        components?.queryItems = [
            URLQueryItem(name: "symbols", value: yahooSymbols),
            URLQueryItem(name: "fields", value: "symbol,regularMarketPrice,regularMarketOpen,regularMarketTime,currency"),
            URLQueryItem(name: "crumb", value: crumb),
        ]
        guard let url = components?.url else { return [:] }

        var request = URLRequest(url: url)
        for (field, value) in Self.baseHeaders(accept: "application/json") {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            return [:]
        }

        let decoded = try decoder.decode(YahooQuoteResponse.self, from: data)
        let byYahooSymbol = Dictionary(uniqueKeysWithValues: decoded.quoteResponse.result.compactMap { item -> (String, YahooQuoteItem)? in
            guard let symbol = item.symbol else { return nil }
            return (symbol, item)
        })

        var quotes: [String: MarketQuote] = [:]
        for pair in sanitizedPairs {
            guard let item = byYahooSymbol[pair.yahoo],
                  let lastPrice = item.regularMarketPrice,
                  let openPrice = item.regularMarketOpen,
                  openPrice != Decimal(0) else {
                continue
            }
            quotes[pair.original] = MarketQuote(
                symbol: pair.original,
                currency: item.currency,
                lastPrice: lastPrice,
                openPrice: openPrice,
                marketTime: item.regularMarketTime
            )
        }
        return quotes
    }

    private func yahooCrumb() async throws -> String? {
        if let crumb, !crumb.isEmpty {
            return crumb
        }

        try await fetchYahooCookies()
        let crumb = try await fetchYahooCrumb()
        self.crumb = crumb
        return crumb
    }

    private func fetchYahooCookies() async throws {
        var request = URLRequest(url: Self.quotePageURL)
        request.httpShouldHandleCookies = true
        for (field, value) in Self.baseHeaders(accept: "text/html,application/xhtml+xml,application/xml") {
            request.setValue(value, forHTTPHeaderField: field)
        }

        _ = try await session.data(for: request)
    }

    private func fetchYahooCrumb() async throws -> String? {
        var request = URLRequest(url: Self.crumbURL)
        request.httpShouldHandleCookies = true
        for (field, value) in Self.baseHeaders(accept: "*/*") {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.setValue("https://finance.yahoo.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.quotePageURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            return nil
        }

        let crumb = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return crumb.isEmpty ? nil : crumb
    }

    private static func yahooSymbol(from symbol: String) -> String {
        var sanitized = symbol
            .replacingOccurrences(of: " ", with: "")
        if let range = sanitized.range(of: #"\.([A-Z])$"#, options: .regularExpression) {
            let suffix = sanitized[range].dropFirst()
            sanitized.replaceSubrange(range, with: "-\(suffix)")
        }
        return sanitized
    }

    private static func baseHeaders(accept: String) -> [String: String] {
        [
            "Accept": accept,
            "Accept-Language": "en-US,en;q=0.9",
            "User-Agent": userAgent,
        ]
    }
}

private struct YahooQuoteResponse: Decodable {
    let quoteResponse: YahooQuoteResult
}

private struct YahooQuoteResult: Decodable {
    let result: [YahooQuoteItem]
}

private struct YahooQuoteItem: Decodable {
    let symbol: String?
    let regularMarketPrice: Decimal?
    let regularMarketOpen: Decimal?
    let regularMarketTime: Date?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case regularMarketPrice
        case regularMarketOpen
        case regularMarketTime
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        self.regularMarketPrice = try container.decodeIfPresent(Decimal.self, forKey: .regularMarketPrice)
        self.regularMarketOpen = try container.decodeIfPresent(Decimal.self, forKey: .regularMarketOpen)
        self.regularMarketTime = try container.decodeYahooDateIfPresent(forKey: .regularMarketTime)
        self.currency = try container.decodeIfPresent(String.self, forKey: .currency)
    }
}

private extension KeyedDecodingContainer {
    func decodeYahooDateIfPresent(forKey key: Key) throws -> Date? {
        if let timestamp = try? decode(Int.self, forKey: key) {
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        if let timestamp = try? decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let string = try? decode(String.self, forKey: key) {
            if let timestamp = TimeInterval(string) {
                return Date(timeIntervalSince1970: timestamp)
            }
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
