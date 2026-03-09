import Foundation

// MARK: - UserProfile
// AI-synthesized user profile, built from all memories.
// Stored in iCloud at Memories/user_profile.json — syncs between Mac and iOS.

struct UserProfile: Codable, Identifiable {
    var id: UUID = UUID()
    var summary: String                 // Rich narrative (5–8 sentences about who the user is)
    var interests: [String]             // Top interests / areas of passion (ranked, contextualized)
    var projects: [String]              // Notable projects with brief descriptions
    var personalFacts: [String]         // Personal background facts (location, family, health, etc.)
    var technicalSkills: [String]       // Technical skills and tools
    var patterns: [String] = []         // Recurring behavioral patterns and work style observations
    var goals: [String] = []            // Short- and long-term goals and aspirations
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
