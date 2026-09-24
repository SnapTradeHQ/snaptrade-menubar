import Foundation
import Testing
@testable import SnapTradeMenuBarApp

struct StatusChangeLabelTests {
    @Test
    func directionUsesTrianglesWithoutSignedPercent() {
        let gain = StatusChangeLabel.format(Decimal(string: "0.01")!)
        let loss = StatusChangeLabel.format(Decimal(string: "-0.01")!)
        let unchanged = StatusChangeLabel.format(0)
        #expect(gain.hasPrefix("▲ "))
        #expect(loss.hasPrefix("▼ "))
        #expect(!loss.contains("-"))
        #expect(!unchanged.contains("▲") && !unchanged.contains("▼"))
        #expect(StatusChangeLabel.format(Decimal(string: "-0.01")!, prefix: "Tue ").hasPrefix("Tue ▼ "))
    }
}
