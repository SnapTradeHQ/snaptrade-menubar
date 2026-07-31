import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let viewModel: PortfolioViewModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var hostingController: NSHostingController<PortfolioMenuView>?

    private let popoverWidth: CGFloat = 340

    init(viewModel: PortfolioViewModel) {
        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        configurePopover()
        updateStatusButton()

        viewModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
                self?.resizeVisiblePopoverAfterLayout()
            }
            .store(in: &cancellables)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.imagePosition = .imageLeft
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: viewModel.menuBarSystemImage, accessibilityDescription: nil)
        button.toolTip = viewModel.menuBarTitle

        if let movement = currentDailyMovementLabel() {
            statusItem.length = NSStatusItem.variableLength
            button.attributedTitle = movement
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func currentDailyMovementLabel() -> NSAttributedString? {
        let snapshot: PortfolioSnapshot
        switch viewModel.state {
        case .connected(let current), .stale(let current, _):
            snapshot = current
        case .disconnected, .loading, .reconnectNeeded, .error:
            return nil
        }

        guard let dayChangePercent = snapshot.dayChangePercent else { return nil }
        let isGain = dayChangePercent >= Decimal(0)
        let magnitude = isGain ? dayChangePercent : dayChangePercent * Decimal(-1)
        let formattedPercent = PercentFormatter.format(magnitude)
        let prefix = marketSessionPrefix(for: snapshot)
        let label = "\(prefix)\(isGain ? "+" : "-")\(formattedPercent)"

        return NSAttributedString(
            string: label,
            attributes: [
                .foregroundColor: isGain ? NSColor.systemGreen : NSColor.systemRed,
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
        startEventMonitoring()
    }

    private func installPopoverContent() {
        let rootView = PortfolioMenuView(viewModel: viewModel) { [weak self] in
            self?.closePopover()
        }
        let hostingController = NSHostingController(rootView: rootView)
        self.hostingController = hostingController
        popover.contentViewController = hostingController
        updatePopoverContentSize()
    }

    private func closePopover() {
        popover.performClose(nil)
        stopEventMonitoring()
    }

    private func startEventMonitoring() {
        stopEventMonitoring()

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
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
            stopEventMonitoring()
        }
    }
}
