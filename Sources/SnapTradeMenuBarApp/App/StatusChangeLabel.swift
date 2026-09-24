import Foundation

enum StatusChangeLabel {
    static func format(_ percent: Decimal, prefix: String = "") -> String {
        let magnitude = percent < 0 ? -percent : percent
        let direction = percent > 0 ? "▲ " : (percent < 0 ? "▼ " : "")
        return "\(prefix)\(direction)\(PercentFormatter.format(magnitude))"
    }
}
