import SwiftUI

// MARK: - ProfileView
// AI-synthesized user profile built from memories.
// Auto-generates periodically; manually refreshable.

struct ProfileView: View {
    @StateObject private var profileMgr = UserProfileManager.shared
    @StateObject private var memMgr = MemoryManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let profile = profileMgr.profile {
                    profileContent(profile)
                } else if profileMgr.isSynthesizing {
                    synthesizingState
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .background(Color.chatBackground)
        .onAppear {
            Task {
                await profileMgr.loadProfile()
                if profileMgr.profile == nil && memMgr.memories.count >= 3 {
                    await profileMgr.synthesize(memories: memMgr.memories)
                }
            }
        }
    }

    // MARK: - Profile content

    @ViewBuilder
    func profileContent(_ profile: UserProfile) -> some View {
        // Header card
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.accentNavi.opacity(0.8), Color.accentNavi.opacity(0.5)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)
                    Text("T")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Ted Svärd")
                        .font(.system(size: 18, weight: .bold))
                    Text(profile.relativeUpdateString)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text("Baserat på \(profile.memoryCountAtGeneration) minnen")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                Spacer()

                // Refresh button
                Button {
                    Task { await profileMgr.synthesize(memories: memMgr.memories) }
                } label: {
                    if profileMgr.isSynthesizing {
                        ProgressView().scaleEffect(0.7)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
                .buttonStyle(.plain)
                .disabled(profileMgr.isSynthesizing)
            }

            // Summary
            Text(profile.summary)
                .font(.system(size: 14))
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.userBubble)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentNavi.opacity(0.2), lineWidth: 0.5)
                )
        )

        // Interests
        if !profile.interests.isEmpty {
            profileSection(title: "Intressen", icon: "sparkles") {
                ChipFlowLayout(items: profile.interests) { interest in
                    Text(interest)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.accentNavi)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.accentNavi.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .strokeBorder(Color.accentNavi.opacity(0.3), lineWidth: 0.5)
                                )
                        )
                }
            }
        }

        // Projects
        if !profile.projects.isEmpty {
            profileSection(title: "Projekt", icon: "folder.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.projects, id: \.self) { project in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentNavi)
                                .padding(.top, 3)
                            Text(project)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.85))
                            Spacer()
                        }
                    }
                }
            }
        }

        // Personal facts
        if !profile.personalFacts.isEmpty {
            profileSection(title: "Om mig", icon: "person.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.personalFacts, id: \.self) { fact in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(Color.secondary.opacity(0.5))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(fact)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.85))
                            Spacer()
                        }
                    }
                }
            }
        }

        // Technical skills
        if !profile.technicalSkills.isEmpty {
            profileSection(title: "Tekniska färdigheter", icon: "cpu.fill") {
                ChipFlowLayout(items: profile.technicalSkills) { skill in
                    Text(skill)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.surfaceHover)
                        )
                }
            }
        }

        // Patterns
        if !profile.patterns.isEmpty {
            profileSection(title: "Beteendemönster", icon: "repeat.circle.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.patterns, id: \.self) { pattern in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.accentNavi.opacity(0.7))
                                .padding(.top, 3)
                            Text(pattern)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.85))
                            Spacer()
                        }
                    }
                }
            }
        }

        // Goals
        if !profile.goals.isEmpty {
            profileSection(title: "Mål & ambitioner", icon: "target") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(profile.goals, id: \.self) { goal in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.green.opacity(0.7))
                                .padding(.top, 1)
                            Text(goal)
                                .font(.system(size: 13))
                                .foregroundColor(.primary.opacity(0.85))
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty / Loading states

    var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accentNavi.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(Color.accentNavi.opacity(0.6))
            }
            VStack(spacing: 8) {
                Text("Ingen profil ännu")
                    .font(.system(size: 18, weight: .semibold))
                Text(memMgr.memories.count < 3
                     ? "Behöver minst 3 minnen. Du har \(memMgr.memories.count) just nu."
                     : "Profilen genereras automatiskt från dina minnen.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if memMgr.memories.count >= 3 {
                Button {
                    Task { await profileMgr.synthesize(memories: memMgr.memories) }
                } label: {
                    Label("Generera profil nu", systemImage: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentNavi))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    var synthesizingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Genererar profil…")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section helper

    @ViewBuilder
    func profileSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.userBubble)
        )
    }
}

// MARK: - Chip flow layout for tags (ProfileView)

struct ChipFlowLayout<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        // Wrapping layout: group into rows of ~3
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(items[i..<min(i+3, items.count)], id: \.self) { item in
                        content(item)
                    }
                    Spacer()
                }
            }
        }
    }
}
