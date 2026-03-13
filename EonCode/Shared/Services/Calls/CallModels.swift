import Foundation

// MARK: - Call Status

enum CallStatus: String, Codable, CaseIterable {
    case active, completed, failed, dialing, placed

    var label: String {
        switch self {
        case .active:    return "Pågående"
        case .completed: return "Avslutad"
        case .failed:    return "Misslyckad"
        case .dialing:   return "Ringer"
        case .placed:    return "Placerad"
        }
    }

    var color: String {
        switch self {
        case .active:    return "34C759"
        case .completed: return "8E8E93"
        case .failed:    return "FF3B30"
        case .dialing:   return "FF9500"
        case .placed:    return "007AFF"
        }
    }
}

enum CallDirection: String, Codable {
    case incoming = "incoming"
    case outbound = "outbound"

    var label: String { self == .incoming ? "Inkommande" : "Utgående" }
    var icon:  String { self == .incoming ? "phone.arrow.down.left" : "phone.arrow.up.right" }
}

// MARK: - Transcript line

struct TranscriptLine: Codable, Identifiable {
    var id:      String { "\(role)_\(timeSec)" }
    let role:    String   // "AI" or "Kund"
    let text:    String
    let timeSec: Double

    var isAgent: Bool { role == "AI" }

    private enum CodingKeys: String, CodingKey {
        case role, text, timeSec = "timeSec"
    }
}

// MARK: - Call

struct Call: Codable, Identifiable {
    let id:          String
    var direction:   CallDirection?
    var from:        String?
    var to:          String?
    var status:      CallStatus
    var agentId:     String?
    var goal:        String?
    var startedAt:   String?
    var endedAt:     String?
    var duration:    Double?
    var transcript:  [TranscriptLine]?
    var liveTranscript: [TranscriptLine]?
    var summary:     String?
    var goalResult:  String?   // "ACHIEVED", "PARTIAL", "NOT_ACHIEVED"
    var analysis:    CallAnalysis?

    // List-view abbreviated fields (from /calls endpoint)
    var transcriptLines: Int?
    var lastLine:       TranscriptLine?

    var durationFormatted: String {
        guard let d = duration else { return "—" }
        let mins = Int(d) / 60
        let secs = Int(d) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
    }

    var startDate: Date? {
        guard let s = startedAt else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    var goalResultLabel: String {
        switch goalResult?.prefix(8) {
        case "ACHIEVED":     return "✅ Uppnått"
        case "PARTIAL":      return "🟡 Delvis"
        case "NOT_ACHIEV":   return "❌ Ej uppnått"
        default:             return ""
        }
    }
}

struct CallAnalysis: Codable {
    var transcript_summary:    String?
    var custom_analysis_data:  [String: String]?
}

// MARK: - Scheduled call

struct ScheduledCall: Codable, Identifiable {
    let id:          String
    var to:          String
    var goal:        String
    var systemPrompt: String?
    var firstMessage: String?
    var scheduledAt: String
    var notes:       String?
    var status:      String   // "pending", "placing", "placed", "failed"
    var createdAt:   String?
    var callId:      String?
    var error:       String?

    var scheduledDate: Date? {
        ISO8601DateFormatter().date(from: scheduledAt)
            ?? DateFormatter.localDateTime.date(from: scheduledAt)
    }

    var statusLabel: String {
        switch status {
        case "pending":  return "Väntar"
        case "placing":  return "Ringer…"
        case "placed":   return "Placerad"
        case "failed":   return "Misslyckad"
        default:         return status
        }
    }
}

// MARK: - Stats

struct CallStats: Codable {
    var today:   DayStats
    var allTime: TotalStats
}

struct DayStats: Codable {
    var total:          Int
    var incoming:       Int
    var outbound:       Int
    var active:         Int
    var completed:      Int
    var avgDurationSec: Int
    var goalsAchieved:  Int
}

struct TotalStats: Codable {
    var total:    Int
    var incoming: Int
    var outbound: Int
}

// MARK: - API Responses

struct CallsResponse: Codable {
    let calls: [Call]
    let total: Int
}

struct ScheduledCallsResponse: Codable {
    let scheduled: [ScheduledCall]
}

// MARK: - DateFormatter helper

extension DateFormatter {
    static let localDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static let displayTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
