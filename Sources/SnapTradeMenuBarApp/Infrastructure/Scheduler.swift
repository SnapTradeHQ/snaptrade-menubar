import Foundation

final class Scheduler: @unchecked Sendable {
    private let interval: TimeInterval
    private let action: () -> Void
    private var timer: Timer?

    init(interval: TimeInterval, action: @escaping () -> Void) {
        self.interval = interval
        self.action = action
    }

    func start() {
        cancel()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.action()
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }
}
