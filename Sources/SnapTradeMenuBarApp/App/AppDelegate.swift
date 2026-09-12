import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = PortfolioViewModel()
    private let updater = AppUpdater()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updater.start()
        statusItemController = StatusItemController(viewModel: viewModel, updater: updater)
        Task {
            await viewModel.start()
        }
    }
}
