import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let viewModel: PortfolioViewModel
    private let updater: AppUpdater
    private let displayPreferences: StatusDisplayPreferences
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var hostingController: NSHostingController<PortfolioMenuView>?
    private var settingsWindow: NSWindow?
    private var expandedSessionBeganAt: TimeInterval = 0

    private let popoverWidth: CGFloat = 340

    init(viewModel: PortfolioViewModel, updater: AppUpdater, displayPreferences: StatusDisplayPreferences) {
        self.viewModel = viewModel
        self.updater = updater
        self.displayPreferences = displayPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        configurePopover()
        updateStatusButton()

        viewModel.$partialSnapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.resizeVisiblePopoverAfterLayout() }
            .store(in: &cancellables)

        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
                self?.resizeVisiblePopoverAfterLayout()
            }
            .store(in: &cancellables)

        displayPreferences.$mode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Published values arrive before the property changes.
                DispatchQueue.main.async { self?.updateStatusButton() }
            }
            .store(in: &cancellables)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        if #available(macOS 27.0, *) {
            statusItem.expandedInterfaceDelegate = self
        } else {
            button.target = self
            button.action = #selector(togglePopover)
        }
        button.imagePosition = .imageLeft
    }

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.delegate = self
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = viewModel.menuBarSystemImage.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil)
        }
        button.toolTip = viewModel.menuBarTitle

        if let movement = currentStatusLabel() {
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = movement
        } else if button.image == nil {
            statusItem.length = NSStatusItem.variableLength
            let fallback: String
            switch viewModel.state {
            case .disconnected: fallback = "Connect"
            default: fallback = "—"
            }
            button.attributedTitle = NSAttributedString(string: fallback)
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.attributedTitle = NSAttributedString(string: "")
        }
        #if DEBUG
        statusItem.length = NSStatusItem.variableLength
        let title = NSMutableAttributedString(string: viewModel.isPreview ? "SAMPLE " : "TEST ", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        title.append(button.attributedTitle)
        button.attributedTitle = title
        button.toolTip = "SnapTrade Menu Bar Test · \(viewModel.menuBarTitle)"
        #endif
    }

    private func currentStatusLabel() -> NSAttributedString? {
        let snapshot: PortfolioSnapshot
        switch viewModel.state {
        case .connected(let current), .stale(let current, _):
            snapshot = current
        case .disconnected, .loading, .reconnectNeeded, .error:
            return nil
        }

        guard !snapshot.hasMultipleCurrencies else { return nil }
        switch displayPreferences.mode {
        case .portfolioValue:
            guard snapshot.missingAccountTotalCount == 0 || snapshot.missingAccountTotalCount == nil,
                  snapshot.totalsByCurrency.count == 1,
                  let total = snapshot.totalsByCurrency.first,
                  let value = total.brokerReported else { return nil }
            return NSAttributedString(string: CurrencyFormatter.format(value, currency: total.currency), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ])
        case .dailyPercent:
            break
        }
        guard let dayChangePercent = snapshot.dayChangePercent else { return nil }
        let isGain = dayChangePercent > Decimal(0)
        let isLoss = dayChangePercent < Decimal(0)
        let prefix = marketSessionPrefix(for: snapshot)
        let label = StatusChangeLabel.format(dayChangePercent, prefix: prefix)

        return NSAttributedString(
            string: label,
            attributes: [
                .foregroundColor: isGain ? NSColor.systemGreen : (isLoss ? NSColor.systemRed : NSColor.labelColor),
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            ]
        )
    }

    private func marketSessionPrefix(for snapshot: PortfolioSnapshot) -> String {
        guard let marketSessionAt = snapshot.marketSessionAt else { return "" }
        guard !Calendar.current.isDateInToday(marketSessionAt) else { return "" }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return "\(formatter.string(from: marketSessionAt)) "
    }

    @objc
    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        installPopoverContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Opening the panel should not select its first button. Tab can still
        // move focus into the controls and display the normal keyboard focus ring.
        hostingController?.view.window?.makeFirstResponder(nil)
        startEventMonitoring()
    }

    private func installPopoverContent() {
        let rootView = PortfolioMenuView(viewModel: viewModel, updater: updater, displayPreferences: displayPreferences, openSettings: { [weak self] in
            self?.showSettings()
        }) { [weak self] in
            self?.closePopover()
        }
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        popover.contentViewController = hostingController
        updatePopoverContentSize()
    }

    private func closePopover() {
        if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
            session.cancel()
        } else {
            dismissPopover()
        }
    }

    private func dismissPopover() {
        popover.performClose(nil)
        stopEventMonitoring()
    }

    private func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 140),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SnapTrade Menu Bar Settings"
            window.contentView = NSHostingView(rootView: MenuBarSettingsView(preferences: displayPreferences))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startEventMonitoring() {
        stopEventMonitoring()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if self.isStatusButtonClick(event) {
                    if self.isSecondStatusButtonClick(event) { self.closePopover() }
                } else {
                    self.closePopover()
                }
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.closePopover()
                    return nil
                }
            } else if self.isStatusButtonClick(event) {
                if self.isSecondStatusButtonClick(event) {
                    self.closePopover()
                    return nil
                }
            } else if event.window !== self.popover.contentViewController?.view.window {
                self.closePopover()
            }
            return event
        }
    }

    private func isSecondStatusButtonClick(_ event: NSEvent) -> Bool {
        guard #available(macOS 27.0, *),
              popover.isShown,
              event.timestamp >= expandedSessionBeganAt else { return false }
        return true
    }

    private func isStatusButtonClick(_ event: NSEvent) -> Bool {
        guard event.type != .keyDown,
              let button = statusItem.button,
              let window = button.window else { return false }
        // Status item clicks can arrive through either event monitor. Compare
        // screen coordinates because the event may belong to another window.
        let clickPoint = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return buttonFrame.contains(clickPoint)
    }

    private func stopEventMonitoring() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func resizeVisiblePopoverAfterLayout() {
        guard popover.isShown else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updatePopoverContentSize()
        }
    }

    private func updatePopoverContentSize() {
        guard let hostingController else { return }
        let fittingSize = hostingController.sizeThatFits(
            in: NSSize(width: popoverWidth, height: CGFloat.greatestFiniteMagnitude)
        )
        popover.contentSize = NSSize(width: popoverWidth, height: ceil(fittingSize.height))
    }
}

extension StatusItemController: NSPopoverDelegate {
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            if #available(macOS 27.0, *), let session = statusItem.expandedInterfaceSession {
                session.cancel()
            }
            stopEventMonitoring()
        }
    }
}

@available(macOS 27.0, *)
extension StatusItemController: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        expandedSessionBeganAt = ProcessInfo.processInfo.systemUptime
        showPopover()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        dismissPopover()
    }
}
