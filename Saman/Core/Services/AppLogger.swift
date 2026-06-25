import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.samanpantry.Saman", category: "app")

    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
