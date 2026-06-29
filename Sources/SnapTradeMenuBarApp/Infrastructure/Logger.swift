import OSLog

enum AppLogger {
    static let auth = Logger(subsystem: "com.snaptrade.menubar", category: "auth")
    static let api = Logger(subsystem: "com.snaptrade.menubar", category: "api")
    static let app = Logger(subsystem: "com.snaptrade.menubar", category: "app")
}
