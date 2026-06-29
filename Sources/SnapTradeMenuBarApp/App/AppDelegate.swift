import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewModel = PortfolioViewModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(viewModel: viewModel)
        Task {
            await viewModel.start()
        }
    }
}
