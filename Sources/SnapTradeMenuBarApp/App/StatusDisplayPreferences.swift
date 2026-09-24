import Combine
import Foundation

enum StatusDisplayMode: String, CaseIterable, Identifiable {
    case dailyPercent
    case portfolioValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyPercent: "Daily change (%)"
        case .portfolioValue: "Portfolio value"
        }
    }
}

enum PortfolioTotalDisplayMode: String, CaseIterable, Identifiable {
    case brokerReported
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .brokerReported: "Broker reported"
        case .both: "Broker reported and calculated"
        }
    }
}

@MainActor
final class StatusDisplayPreferences: ObservableObject {
    private static let statusKey = "SnapTradeMenuBar.StatusDisplayMode.v1"
    private static let totalsKey = "SnapTradeMenuBar.PortfolioTotalDisplayMode.v1"

    @Published var mode: StatusDisplayMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.statusKey) }
    }

    @Published var totalMode: PortfolioTotalDisplayMode {
        didSet { UserDefaults.standard.set(totalMode.rawValue, forKey: Self.totalsKey) }
    }

    init() {
        mode = UserDefaults.standard.string(forKey: Self.statusKey)
            .flatMap(StatusDisplayMode.init(rawValue:)) ?? .dailyPercent
        totalMode = UserDefaults.standard.string(forKey: Self.totalsKey)
            .flatMap(PortfolioTotalDisplayMode.init(rawValue:)) ?? .brokerReported
    }
}
