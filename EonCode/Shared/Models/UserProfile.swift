import Foundation

// MARK: - UserProfile
// AI-synthesized user profile, built from all memories.
// Stored in iCloud at Memories/user_profile.json — syncs between Mac and iOS.

struct UserProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var summary: String                 // Main narrative (3–5 sentences about who the user is)
    var interests: [String]             // Top interests / areas of passion (ranked)
    var projects: [String]              // Notable projects the user has worked on
    var personalFacts: [String]         // Personal background facts
    var technicalSkills: [String]       // Technical skills and tools
    var createdAt: Date
    var updatedAt: Date
    var memoryCountAtGeneration: Int    // How many memories existed when this was generated

    // Human-readable "last updated" string
    var relativeUpdateString: String {
        let diff = Date().timeIntervalSince(updatedAt)
        if diff < 3600 { return "Uppdaterad precis" }
        if diff < 86400 { return "Uppdaterad \(Int(diff/3600))h sedan" }
        return "Uppdaterad \(Int(diff/86400))d sedan"
    }
}
