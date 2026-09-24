import SwiftUI

struct MenuBarSettingsView: View {
    @ObservedObject var preferences: StatusDisplayPreferences

    private let labelWidth: CGFloat = 100
    private let rowSpacing: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: rowSpacing) {
                Text("Menu bar")
                    .frame(width: labelWidth, alignment: .trailing)
                Picker("Menu bar", selection: $preferences.mode) {
                    ForEach(StatusDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: rowSpacing) {
                    Text("Total assets")
                        .frame(width: labelWidth, alignment: .trailing)
                    Picker("Total assets", selection: $preferences.totalMode) {
                        ForEach(PortfolioTotalDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                Text("Calculated totals use holdings and cash. They may differ from broker totals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, labelWidth + rowSpacing)
            }
        }
        .padding(24)
        .frame(width: 440, height: 140, alignment: .topLeading)
    }
}
