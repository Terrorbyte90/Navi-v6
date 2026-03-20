import Foundation
import SwiftUI
import os

// MARK: - App Logger

enum NaviLog {
    private static let logger = Logger(subsystem: "com.navi.app", category: "general")

    static func error(_ message: String, error: Error? = nil) {
        if let error {
            logger.error("\(message): \(error.localizedDescription)")
        } else {
            logger.error("\(message)")
        }
    }

    static func warning(_ message: String) {
        logger.warning("\(message)")
    }

    static func info(_ message: String) {
        logger.info("\(message)")
    }
}

// MARK: - String
extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }

    func truncated(to length: Int, suffix: String = "…") -> String {
        count > length ? String(prefix(length)) + suffix : self
    }

    var lines: [String] { components(separatedBy: "\n") }

    var lineCount: Int { lines.count }

    func ranges(of substring: String, options: CompareOptions = []) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = startIndex
        while let range = range(of: substring, options: options, range: start..<endIndex) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }
}

// MARK: - URL
extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }

    var modificationDate: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
    }

    func appending(components: [String]) -> URL {
        components.reduce(self) { $0.appendingPathComponent($1) }
    }
}

// MARK: - Date
extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }

    var relativeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "sv_SE")
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    static func from(iso8601 string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}

// MARK: - Data
extension Data {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: self)
    }
}

extension Encodable {
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    func encodedString() throws -> String {
        String(data: try encoded(), encoding: .utf8) ?? ""
    }
}

// MARK: - Keyboard Helpers

/// Dismiss the software keyboard. No-op on macOS.
func dismissKeyboard() {
    #if os(iOS)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
    #endif
}

// MARK: - View Modifiers
extension View {

    func glassBackground(radius: CGFloat = 16, opacity: Double = 0.15) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    func cardStyle() -> some View {
        self
            .padding()
            .glassBackground()
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Color (Navi dark teal palette)
extension Color {
    static var codeBackground: Color {
        Color(red: 0.10, green: 0.10, blue: 0.11)
    }
    static var chatBackground: Color {
        #if os(macOS)
        Color(NSColor.windowBackgroundColor)
        #else
        // Dark forest teal — always dark
        Color(UIColor { _ in UIColor(red: 0.059, green: 0.090, blue: 0.071, alpha: 1) })
        #endif
    }
    static var sidebarBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor { _ in UIColor(red: 0.043, green: 0.067, blue: 0.055, alpha: 1) })
        #endif
    }
    /// Bright mint accent — Navi dark teal theme (#1ECC9A)
    static var accentNavi: Color { Color(red: 0.118, green: 0.800, blue: 0.604) }
    static var assistantBubble: Color { Color.clear }
    static var userBubble: Color {
        #if os(macOS)
        Color(NSColor.controlColor)
        #else
        Color(UIColor { _ in UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1) })
        #endif
    }
    static var inputBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(UIColor { _ in UIColor(red: 0.10, green: 0.15, blue: 0.12, alpha: 1) })
        #endif
    }
    static var inputBorder: Color {
        #if os(macOS)
        Color(NSColor.separatorColor)
        #else
        Color(UIColor.separator)
        #endif
    }
    static var surfaceHover: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor).opacity(0.6)
        #else
        Color(UIColor { _ in UIColor(red: 0.10, green: 0.15, blue: 0.12, alpha: 1) })
        #endif
    }
    static var dividerColor: Color {
        #if os(macOS)
        Color(NSColor.separatorColor)
        #else
        Color(UIColor.separator)
        #endif
    }
}

// MARK: - Int64
extension Int64 {
    var formattedFileSize: String {
        let bytes = Double(self)
        if bytes < 1024 { return "\(self) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", bytes / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", bytes / (1024 * 1024)) }
        return String(format: "%.1f GB", bytes / (1024 * 1024 * 1024))
    }
}

// MARK: - Task
extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Int
extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
