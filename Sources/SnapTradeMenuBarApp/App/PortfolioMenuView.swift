import SwiftUI

struct PortfolioMenuView: View {
    @ObservedObject var viewModel: PortfolioViewModel
    var close: () -> Void = {}

    private let panelWidth: CGFloat = 340

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
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            headerControls
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
        case .waitingForDeviceApproval:
            return "Waiting for SnapTrade approval..."
        case .error:
            return "Refresh failed"
        }
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
        case .stale, .reconnectNeeded, .waitingForDeviceApproval, .error:
            return true
        }
    }

    private var showsHeaderText: Bool {
        switch viewModel.state {
        case .disconnected:
            return false
        case .connected, .loading, .stale, .reconnectNeeded, .waitingForDeviceApproval, .error:
            return true
        }
    }

    private var contentSpacing: CGFloat {
        switch viewModel.state {
        case .connected:
            return 10
        case .disconnected, .loading, .stale, .reconnectNeeded, .waitingForDeviceApproval, .error:
            return 16
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .disconnected:
            disconnectedPrompt
        case .loading:
            Text("Refreshing portfolio with SnapTrade...")
                .foregroundStyle(.secondary)
        case .connected(let snapshot):
            portfolio(snapshot)
        case .stale(let snapshot, let message):
            errorBanner(title: "Refresh failed", message: message)
            portfolio(snapshot)
        case .reconnectNeeded(let message):
            errorBanner(title: "SnapTrade reconnect needed", message: message)
        case .waitingForDeviceApproval(let display):
            VStack(alignment: .leading, spacing: 8) {
                Text("Code: \(display.userCode)")
                    .font(.title3.monospaced().weight(.semibold))
                Text(display.verificationURI)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
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
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Assets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(snapshot.formattedTotal)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
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

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let formattedDayChange = position.formattedDayChange,
                               let formattedDayChangePercent = position.formattedDayChangePercent,
                               let dayChange = position.dayChange {
                                Text("\(formattedDayChange) \(formattedDayChangePercent)")
                                    .foregroundStyle(dayChange >= Decimal(0) ? .green : .red)
                            }

                            if let formattedPercent = position.formattedPercent {
                                Text(formattedPercent)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2.monospacedDigit())
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
                Image(systemName: "gearshape")
                    .imageScale(.large)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .focusable(false)
            .fixedSize()
            .help("Settings and actions")
        }
    }

    private var canRefresh: Bool {
        if viewModel.isRefreshing { return false }
        switch viewModel.state {
        case .connected, .stale, .error:
            return true
        case .disconnected, .loading, .reconnectNeeded, .waitingForDeviceApproval:
            return false
        }
    }

    @ViewBuilder
    private var menuActions: some View {
        switch viewModel.state {
        case .disconnected:
            Button("Settings") {
                viewModel.showSettings()
            }
            Divider()
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
            Button("Settings") {
                viewModel.showSettings()
            }
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
            Button("Settings") {
                viewModel.showSettings()
            }
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
        case .loading, .waitingForDeviceApproval:
            Button("Settings") {
                viewModel.showSettings()
            }
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
