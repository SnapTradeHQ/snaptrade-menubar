import SwiftUI

struct PortfolioMenuView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var close: () -> Void = {}

    private let panelWidth: CGFloat = 340
    private let dashboardURL = URL(string: "https://dashboard.snaptrade.com/")!

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            if !isDisconnected {
                header
            }

            content
        }
        .padding(16)
        .frame(width: panelWidth, alignment: .topLeading)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .top) {
            if showsHeaderText {
                VStack(alignment: .leading, spacing: 2) {
                    if showsTitle {
                        Text("SnapTrade Portfolio")
                            .font(.headline)
                    }
                    subtitleView
                }
            }
            Spacer()
            headerControls
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch viewModel.state {
        case .connected(let snapshot):
            if viewModel.isRefreshing {
                syncProgressView(fallbackMessage: "Syncing latest portfolio...")
            } else {
                timestampSubtitle("Last updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))", snapshot: snapshot)
            }
        case .stale(let snapshot, _):
            if viewModel.isRefreshing {
                syncProgressView(fallbackMessage: "Retrying portfolio sync...")
            } else {
                timestampSubtitle("Showing last value from \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))", snapshot: snapshot)
            }
        case .loading:
            if viewModel.isRefreshing {
                syncProgressView(fallbackMessage: "Syncing latest portfolio...")
            } else {
                subtitleText(subtitle)
            }
        default:
            subtitleText(subtitle)
        }
    }

    private func syncProgressView(fallbackMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                subtitleText(syncProgressLabel(fallback: fallbackMessage))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if case .accounts(let completed, let total) = viewModel.syncProgress, total > 0 {
                    Text("\(completed) of \(total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if case .accounts(let completed, let total) = viewModel.syncProgress, total > 0 {
                ProgressView(value: Double(completed), total: Double(total))
                    .accessibilityLabel("Portfolio sync progress")
                    .accessibilityValue("\(completed) of \(total) accounts")
            } else {
                ProgressView()
                    .accessibilityLabel(syncProgressLabel(fallback: fallbackMessage))
            }
        }
        .progressViewStyle(.linear)
        .controlSize(.small)
        .frame(width: 210, alignment: .leading)
    }

    private func syncProgressLabel(fallback: String) -> String {
        switch viewModel.syncProgress {
        case .loadingAccounts:
            return "Loading accounts..."
        case .accounts:
            return "Syncing latest portfolio..."
        case .finalizing:
            return "Updating market prices..."
        case nil:
            return fallback
        }
    }

    private var subtitle: String {
        switch viewModel.state {
        case .connected(let snapshot):
            if viewModel.isRefreshing {
                return "Syncing latest portfolio..."
            }
            return "Last updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
        case .stale(let snapshot, _):
            if viewModel.isRefreshing {
                return "Retrying portfolio sync..."
            }
            return "Showing last value from \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))"
        case .disconnected:
            return "Connect to show your total assets."
        case .loading(let message):
            return message
        case .reconnectNeeded:
            return "SnapTrade reconnect needed"
        case .error:
            return "Refresh failed"
        }
    }

    private func disabledConnectionCount(_ snapshot: PortfolioSnapshot) -> Int? {
        guard let disabledConnections = snapshot.disabledConnections,
              disabledConnections > 0 else {
            return nil
        }
        return disabledConnections
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func timestampSubtitle(_ text: String, snapshot: PortfolioSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            subtitleText(text)

            if let disabledConnections = disabledConnectionCount(snapshot) {
                Text(" · ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    NSWorkspace.shared.open(dashboardURL)
                } label: {
                    Text("\(disabledConnections) disabled")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.link)
                    .help("Open SnapTrade dashboard")
            }
        }
        .lineLimit(1)
    }

    private var isLoading: Bool {
        if viewModel.isRefreshing { return true }
        if case .loading = viewModel.state { return true }
        return false
    }

    private var isDisconnected: Bool {
        if case .disconnected = viewModel.state { return true }
        return false
    }

    private var showsTitle: Bool {
        switch viewModel.state {
        case .connected, .disconnected, .loading:
            return false
        case .stale, .reconnectNeeded, .error:
            return true
        }
    }

    private var showsHeaderText: Bool {
        switch viewModel.state {
        case .disconnected:
            return false
        case .connected, .loading, .stale, .reconnectNeeded, .error:
            return true
        }
    }

    private var contentSpacing: CGFloat {
        switch viewModel.state {
        case .connected:
            return 10
        case .disconnected, .loading, .stale, .reconnectNeeded, .error:
            return 16
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .disconnected:
            disconnectedPrompt
        case .loading:
            EmptyView()
        case .connected(let snapshot):
            portfolio(snapshot)
        case .stale(let snapshot, let message):
            errorBanner(title: "Refresh failed", message: message)
            portfolio(snapshot)
        case .reconnectNeeded(let message):
            errorBanner(title: "SnapTrade reconnect needed", message: message)
        case .error(let message):
            errorBanner(title: "Refresh failed", message: message)
        }
    }

    private var disconnectedPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect your portfolio")
                        .font(.headline)
                    Text("View total assets from the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                headerControls
            }

            Button {
                closeMenu()
                Task { await viewModel.connect() }
            } label: {
                Label("Connect SnapTrade", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func portfolio(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Total Assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 14) {
                    totalAssetMetric(
                        label: "Broker reported",
                        value: snapshot.formattedTotal,
                        accessibilityValue: snapshot.formattedTotal
                    )

                    totalAssetMetric(
                        label: "Calculated",
                        value: snapshot.formattedCalculatedTotal ?? "Unavailable",
                        accessibilityValue: snapshot.formattedCalculatedTotal ?? "Unavailable"
                    )
                }

                if let difference = snapshot.formattedCalculatedDifference {
                    Text("Difference \(difference)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Difference between calculated and broker reported total")
                        .accessibilityValue(difference)
                } else {
                    Text("Calculated value needs complete USD position and cash data")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !snapshot.positions.isEmpty || !snapshot.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(snapshot.positions.isEmpty ? "Accounts" : "Top Positions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !snapshot.positions.isEmpty {
                            Text("Top \(snapshot.positions.count)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if snapshot.positions.isEmpty {
                        accountList(snapshot.accounts)
                    } else {
                        positionList(snapshot.positions)
                    }
                }
            }
        }
    }

    private func totalAssetMetric(
        label: String,
        value: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private func positionList(_ positions: [PortfolioPosition]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(positions) { position in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(position.symbol)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)

                            if let formattedPrice = position.formattedPrice {
                                Text(formattedPrice)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            if let formattedDayChangePercent = position.formattedDayChangePercent,
                               let dayChange = position.dayChange {
                                Text(formattedDayChangePercent)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(dayChange >= Decimal(0) ? .green : .red)
                                    .lineLimit(1)
                            }
                        }

                        if let displayName = position.displayName, displayName != position.symbol {
                            Text(displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(position.formattedValue)
                            .font(.callout.monospacedDigit())

                        if let formattedPercent = position.formattedPercent {
                            Text(formattedPercent)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func accountList(_ accounts: [PortfolioAccount]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(accounts) { account in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayName)
                                .lineLimit(1)
                            Text(account.institutionName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(account.formattedValue)
                            .font(.callout.monospacedDigit())
                    }
                }
            }
        }
        .frame(maxHeight: 460)
    }

    private func errorBanner(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var headerControls: some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if canRefresh {
                Button {
                    Task { await viewModel.refreshNow() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Refresh portfolio")
            }

            Menu {
                menuActions
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .focusable(false)
            .fixedSize()
            .help("Actions")
        }
    }

    private var canRefresh: Bool {
        if viewModel.isRefreshing { return false }
        switch viewModel.state {
        case .connected, .stale, .error:
            return true
        case .disconnected, .loading, .reconnectNeeded:
            return false
        }
    }

    @ViewBuilder
    private var menuActions: some View {
        switch viewModel.state {
        case .disconnected:
            Button("Relaunch") {
                viewModel.relaunch()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        case .connected, .stale, .error:
            Button("Refresh") {
                Task { await viewModel.refreshNow() }
            }
            Button("Reconnect SnapTrade") {
                closeMenu()
                Task { await viewModel.reconnect() }
            }
            Divider()
            Button("Disconnect", role: .destructive) {
                closeMenu()
                Task {
                    await viewModel.disconnect()
                }
            }
            Divider()
            Button("Relaunch") {
                viewModel.relaunch()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        case .reconnectNeeded:
            Button("Reconnect SnapTrade") {
                closeMenu()
                Task { await viewModel.reconnect() }
            }
            Divider()
            Button("Disconnect", role: .destructive) {
                closeMenu()
                Task {
                    await viewModel.disconnect()
                }
            }
            Divider()
            Button("Relaunch") {
                viewModel.relaunch()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        case .loading:
            Button("Disconnect", role: .destructive) {
                closeMenu()
                Task {
                    await viewModel.disconnect()
                }
            }
            Divider()
            Button("Relaunch") {
                viewModel.relaunch()
            }
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private func closeMenu() {
        close()
    }
}
