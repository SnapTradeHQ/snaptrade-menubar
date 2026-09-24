import SwiftUI

struct PortfolioMenuView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    @ObservedObject var updater: AppUpdater
    @ObservedObject var displayPreferences: StatusDisplayPreferences
    var openSettings: () -> Void = {}
    var close: () -> Void = {}
    @State private var showsTotalsExplanation = false

    private let panelWidth: CGFloat = 340
    private let connectionsURL = URL(string: "https://my.snaptrade.com/")!

    var body: some View {
        VStack(alignment: .leading, spacing: contentSpacing) {
            if !isDisconnected {
                header
            }

            content
        }
        .padding(16)
        .frame(width: panelWidth, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
                    if viewModel.isPreview {
                        Text("Sample portfolio · No live accounts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        subtitleView
                    }
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
                    openConnections()
                } label: {
                    Text("\(disabledConnections) disabled")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.link)
                .help("Manage connections on my.snaptrade.com")
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
            if let snapshot = viewModel.partialSnapshot { partialPortfolio(snapshot) }
        case .connected(let snapshot):
            portfolio(snapshot)
        case .stale(let snapshot, let message):
            errorBanner(title: "Refresh failed", message: message)
            portfolio(snapshot)
        case .reconnectNeeded(let message):
            errorBanner(title: "SnapTrade reconnect needed", message: message)
            if let snapshot = viewModel.partialSnapshot { partialPortfolio(snapshot) }
        case .error(let message):
            errorBanner(title: "Refresh failed", message: message)
            if let snapshot = viewModel.partialSnapshot { partialPortfolio(snapshot) }
        }
    }

    private func partialPortfolio(_ snapshot: PortfolioSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Partial portfolio · \(viewModel.partialAccountCount) of \(viewModel.totalAccountCount) accounts loaded")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            portfolio(snapshot)
            if !viewModel.isRefreshing {
                Button("Retry sync") { Task { await viewModel.refreshNow() } }
            }
        }
    }

    private var disconnectedPrompt: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect your portfolio")
                        .font(.headline)
                    Text("See your portfolio from the menu bar.")
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
                HStack(spacing: 4) {
                    Text(viewModel.partialSnapshot == nil ? "Total Assets" : "Total Assets (partial)")
                    Button {
                        showsTotalsExplanation.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("About portfolio totals")
                    .popover(isPresented: $showsTotalsExplanation, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("About portfolio totals")
                                .font(.headline)
                            Text("Broker reported totals come from connected accounts. Calculated totals use holdings and cash. They can differ, and no currency conversion is applied.")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(width: 280)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ForEach(snapshot.visibleCurrencyTotals) { total in
                    VStack(alignment: .leading, spacing: 6) {
                        if snapshot.hasMultipleCurrencies {
                            Text(total.currency)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            let reported = total.brokerReported.map { CurrencyFormatter.format($0, currency: total.currency) } ?? "Unavailable"
                            let isPartial = (total.missingAccountCount ?? 0) > 0 && total.brokerReported != nil
                            totalAssetMetric(
                                label: isPartial ? "Broker reported (partial)" : "Broker reported",
                                value: reported,
                                accessibilityValue: reported,
                                prominent: displayPreferences.totalMode == .brokerReported,
                                showsLabel: displayPreferences.totalMode == .both || isPartial || total.brokerReported == nil
                            )
                            if displayPreferences.totalMode == .both {
                                let calculated = total.calculated.map { CurrencyFormatter.format($0, currency: total.currency) } ?? "Unavailable"
                                totalAssetMetric(label: "Calculated", value: calculated, accessibilityValue: calculated)
                            }
                        }
                        if displayPreferences.totalMode == .both, let reason = total.comparisonUnavailableReason {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let missing = snapshot.missingAccountTotalCount, missing > 0 {
                    Text("Totals incomplete: \(missing) account\(missing == 1 ? " is" : "s are") missing a broker-reported value.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if snapshot.visibleCurrencyTotals.isEmpty {
                    Text("No nonzero totals to show.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        ForEach(Array(Set(snapshot.positions.map(\.currency))).sorted(), id: \.self) { currency in
                            if snapshot.hasMultipleCurrencies {
                                Text(currency)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            positionList(snapshot.positions.filter { $0.currency == currency })
                        }
                    }
                }
            }
        }
    }

    private func totalAssetMetric(
        label: String,
        value: String,
        accessibilityValue: String,
        prominent: Bool = false,
        showsLabel: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: prominent ? 24 : 20, weight: .semibold, design: .rounded).monospacedDigit())
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
            }

            ActionsMenuButton(items: actionMenuItems)
                .frame(width: 24, height: 24)
                .help("Actions")
        }
    }

    private var actionMenuItems: [ActionsMenuButton.Item] {
        var items: [ActionsMenuButton.Item] = [
            .action("Settings…") { openSettings() },
            .separator,
        ]
        if updater.isAvailable {
            items.append(.action("Check for Updates…", enabled: updater.canCheckForUpdates) {
                closeMenu()
                updater.checkForUpdates()
            })
            items.append(.separator)
        }
        if viewModel.isPreview {
            items.append(.action("Quit preview") { NSApp.terminate(nil) })
            return items
        }

        items.append(.action("Add or Remove Connections…") { openConnections() })
        items.append(.separator)
        switch viewModel.state {
        case .disconnected:
            break
        case .connected, .stale, .error:
            items.append(.action("Refresh") {
                Task { await viewModel.refreshNow() }
            })
            items.append(.action("Reconnect SnapTrade") {
                closeMenu()
                Task { await viewModel.reconnect() }
            })
            items.append(.separator)
            items.append(disconnectAction)
            items.append(.separator)
        case .reconnectNeeded:
            items.append(.action("Reconnect SnapTrade") {
                closeMenu()
                Task { await viewModel.reconnect() }
            })
            items.append(.separator)
            items.append(disconnectAction)
            items.append(.separator)
        case .loading:
            items.append(disconnectAction)
            items.append(.separator)
        }
        items.append(.action("Relaunch") { viewModel.relaunch() })
        items.append(.action("Quit") { NSApp.terminate(nil) })
        return items
    }

    private var disconnectAction: ActionsMenuButton.Item {
        .action("Disconnect") {
            closeMenu()
            Task { await viewModel.disconnect() }
        }
    }

    private func openConnections() {
        closeMenu()
        NSWorkspace.shared.open(connectionsURL)
    }

    private func closeMenu() {
        close()
    }
}
