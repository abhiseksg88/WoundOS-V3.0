import Foundation
import UIKit
import os

// MARK: - Crash Logger

/// Persistent logger that writes to both os.Logger (Console.app) and a
/// rotating log file on disk. Testers can export the log file for debugging.
///
/// Usage:
///   CrashLogger.shared.log("message", category: .capture)
///   CrashLogger.shared.error("bad thing", category: .measurement, error: someError)
///
/// The on-disk log is designed to be copied into a Claude prompt for analysis.
final class CrashLogger {

    static let shared = CrashLogger()

    // MARK: - Categories

    enum Category: String {
        case app = "App"
        case capture = "Capture"
        case boundary = "Boundary"
        case measurement = "Measurement"
        case segmentation = "Segmentation"
        case storage = "Storage"
        case network = "Network"
        case coordinator = "Coordinator"
    }

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"
    }

    // MARK: - Properties

    private let subsystem = "com.woundos.app"
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.woundos.crashlogger", qos: .utility)
    private var fileHandle: FileHandle?
    private let maxFileSize: UInt64 = 2 * 1024 * 1024 // 2 MB per log file
    private let maxLogFiles = 5

    private lazy var logDirectory: URL = {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("CrashLogs", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var currentLogFile: URL {
        logDirectory.appendingPathComponent("woundos_current.log")
    }

    /// os.Logger instances per category for structured system logging
    private var loggers: [Category: Logger] = [:]

    // MARK: - Init

    private init() {
        openLogFile()
        installCrashHandlers()
        logSessionHeader()
    }

    deinit {
        fileHandle?.closeFile()
    }

    /// Force-flush the log file to disk. Called from signal handlers
    /// where the private fileHandle isn't directly accessible.
    func flushToDisk() {
        fileHandle?.synchronizeFile()
    }

    // MARK: - Public API

    func log(_ message: String, category: Category, level: Level = .info, file: String = #file, line: Int = #line, function: String = #function) {
        let fileName = (file as NSString).lastPathComponent
        let entry = formatEntry(level: level, category: category, message: message, file: fileName, line: line, function: function)

        // Write to os.Logger
        let logger = osLogger(for: category)
        switch level {
        case .debug:    logger.debug("\(entry, privacy: .public)")
        case .info:     logger.info("\(entry, privacy: .public)")
        case .warning:  logger.warning("\(entry, privacy: .public)")
        case .error:    logger.error("\(entry, privacy: .public)")
        case .fault:    logger.fault("\(entry, privacy: .public)")
        }

        // Write to file
        writeToFile(entry)
    }

    func error(_ message: String, category: Category, error: Error? = nil, file: String = #file, line: Int = #line, function: String = #function) {
        var fullMessage = message
        if let error {
            fullMessage += " | Error: \(error.localizedDescription) | Type: \(type(of: error))"
            fullMessage += " | Debug: \(String(describing: error))"
        }
        log(fullMessage, category: category, level: .error, file: file, line: line, function: function)
    }

    func fault(_ message: String, category: Category, file: String = #file, line: Int = #line, function: String = #function) {
        log(message, category: category, level: .fault, file: file, line: line, function: function)
    }

    /// Log key-value diagnostic data (e.g., mesh stats, capture params)
    func logDiagnostics(_ title: String, category: Category, data: [String: Any]) {
        var lines = ["--- \(title) ---"]
        for (key, value) in data.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(key): \(value)")
        }
        lines.append("--- END \(title) ---")
        log(lines.joined(separator: "\n"), category: category, level: .info)
    }

    // MARK: - Log Export

    /// Returns the combined log content as a string, ready to paste into Claude.
    func exportLogs() -> String {
        var combined = ""

        combined += "=== WoundOS Crash Logs Export ===\n"
        combined += "Exported: \(ISO8601DateFormatter().string(from: Date()))\n"
        combined += "Device: \(deviceModel())\n"
        combined += "iOS: \(UIDevice.current.systemVersion)\n"
        combined += "App: \(appVersion())\n"
        combined += "================================\n\n"

        // Read archived logs (oldest first) then current
        let archivedFiles = archivedLogFiles().sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in archivedFiles {
            if let content = try? String(contentsOf: file, encoding: .utf8) {
                combined += "--- \(file.lastPathComponent) ---\n"
                combined += content
                combined += "\n"
            }
        }

        // Current log
        fileHandle?.synchronizeFile()
        if let current = try? String(contentsOf: currentLogFile, encoding: .utf8) {
            combined += "--- CURRENT SESSION ---\n"
            combined += current
        }

        return combined
    }

    /// URL to the current log file (for sharing via UIActivityViewController)
    func logFileURLs() -> [URL] {
        var urls = archivedLogFiles().sorted { $0.lastPathComponent < $1.lastPathComponent }
        if fileManager.fileExists(atPath: currentLogFile.path) {
            fileHandle?.synchronizeFile()
            urls.append(currentLogFile)
        }
        return urls
    }

    /// Clears all logs
    func clearLogs() {
        queue.async { [weak self] in
            guard let self else { return }
            self.fileHandle?.closeFile()
            let files = (try? self.fileManager.contentsOfDirectory(at: self.logDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? self.fileManager.removeItem(at: file)
            }
            self.openLogFile()
            self.logSessionHeader()
        }
    }

    // MARK: - Crash Handlers

    private func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let logger = CrashLogger.shared
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            let message = """
            UNCAUGHT EXCEPTION
            Name: \(exception.name.rawValue)
            Reason: \(exception.reason ?? "unknown")
            Stack trace:
            \(symbols)
            """
            logger.fault(message, category: .app)
            logger.flushToDisk()
        }

        installSignalHandler(SIGSEGV)
        installSignalHandler(SIGABRT)
        installSignalHandler(SIGBUS)
        installSignalHandler(SIGFPE)
        installSignalHandler(SIGILL)
        installSignalHandler(SIGTRAP)
    }

    private func installSignalHandler(_ sig: Int32) {
        var action = sigaction()
        action.__sigaction_u = unsafeBitCast(
            crashSignalHandler as @convention(c) (Int32) -> Void,
            to: __sigaction_u.self
        )
        action.sa_flags = 0
        sigaction(sig, &action, nil)
    }

    // MARK: - File Management

    private func openLogFile() {
        if !fileManager.fileExists(atPath: currentLogFile.path) {
            fileManager.createFile(atPath: currentLogFile.path, contents: nil)
        }
        fileHandle = FileHandle(forWritingAtPath: currentLogFile.path)
        fileHandle?.seekToEndOfFile()
    }

    private func writeToFile(_ entry: String) {
        queue.async { [weak self] in
            guard let self, let data = (entry + "\n").data(using: .utf8) else { return }
            self.fileHandle?.write(data)

            // Rotate if file too large
            if let attrs = try? self.fileManager.attributesOfItem(atPath: self.currentLogFile.path),
               let size = attrs[.size] as? UInt64, size > self.maxFileSize {
                self.rotateLogFile()
            }
        }
    }

    private func rotateLogFile() {
        fileHandle?.closeFile()

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archivedName = "woundos_\(timestamp).log"
        let archivedURL = logDirectory.appendingPathComponent(archivedName)

        try? fileManager.moveItem(at: currentLogFile, to: archivedURL)

        // Prune old archives
        let archives = archivedLogFiles()
        if archives.count > maxLogFiles {
            let toDelete = archives.sorted { $0.lastPathComponent < $1.lastPathComponent }
                .prefix(archives.count - maxLogFiles)
            for file in toDelete {
                try? fileManager.removeItem(at: file)
            }
        }

        openLogFile()
    }

    private func archivedLogFiles() -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(at: logDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("woundos_") && $0.lastPathComponent != "woundos_current.log" }
    }

    // MARK: - Formatting

    private func formatEntry(level: Level, category: Category, message: String, file: String, line: Int, function: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        return "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(file):\(line) \(function) — \(message)"
    }

    private lazy var dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func osLogger(for category: Category) -> Logger {
        if let existing = loggers[category] { return existing }
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = logger
        return logger
    }

    // MARK: - Session Header

    private func logSessionHeader() {
        let header = """

        ========================================
        WoundOS Session Started
        Time: \(ISO8601DateFormatter().string(from: Date()))
        Device: \(deviceModel())
        iOS: \(UIDevice.current.systemVersion)
        App: \(appVersion()) (\(buildNumber()))
        ========================================
        """
        writeToFile(header)
    }

    // MARK: - Device Info

    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "Unknown"
            }
        }
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private func buildNumber() -> String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}

// MARK: - Signal Handler (C function — must be top-level)

private func crashSignalHandler(signal: Int32) {
    let signalName: String
    switch signal {
    case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
    case SIGABRT: signalName = "SIGABRT (Abort)"
    case SIGBUS:  signalName = "SIGBUS (Bus Error)"
    case SIGFPE:  signalName = "SIGFPE (Floating Point Exception)"
    case SIGILL:  signalName = "SIGILL (Illegal Instruction)"
    case SIGTRAP: signalName = "SIGTRAP (Trap)"
    default:      signalName = "Signal \(signal)"
    }

    let message = """
    FATAL SIGNAL: \(signalName)
    Thread: \(Thread.current)
    Stack: \(Thread.callStackSymbols.joined(separator: "\n"))
    """
    CrashLogger.shared.fault(message, category: .app)
    CrashLogger.shared.flushToDisk()

    // Re-raise with default handler so the system crash report is also generated
    Darwin.signal(signal, SIG_DFL)
    raise(signal)
}
