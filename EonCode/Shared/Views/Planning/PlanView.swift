import SwiftUI

// MARK: - PlanView

struct PlanView: View {
    @StateObject private var manager = PlanManager.shared
    @State private var inputText = ""
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    var plan: ProjectPlan? { manager.activePlan }

    var body: some View {
        VStack(spacing: 0) {
            planTopBar
            Divider().opacity(0.12)

            if let plan {
                chatArea(plan: plan)
            } else {
                planEmptyState
            }
        }
        .background(Color.chatBackground)
        .onAppear {
            if manager.activePlan == nil, let first = manager.plans.first {
                manager.activePlan = first
            }
        }
    }

    // MARK: - Top bar

    var planTopBar: some View {
        HStack(spacing: 8) {
            if let plan {
                // Status menu
                Menu {
                    ForEach(PlanStatus.allCases, id: \.self) { status in
                        Button {
                            manager.updateStatus(plan, status: status)
                        } label: {
                            Label(status.rawValue, systemImage: status.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: plan.status.icon)
                            .font(.system(size: 10))
                        Text(plan.status.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

                // Model picker
                Menu {
                    ForEach(ClaudeModel.allCases) { model in
                        Button(model.displayName) {
                            if let idx = manager.plans.firstIndex(where: { $0.id == plan.id }) {
                                manager.plans[idx].model = model
                                manager.activePlan?.model = model
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "cpu").font(.system(size: 10))
                        Text(plan.model.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // New plan
            Button {
                sendTask?.cancel()
                _ = manager.newPlan()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Chat area

    @ViewBuilder
    func chatArea(plan: ProjectPlan) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    // Extracted plan card pinned at top
                    if let extracted = plan.extractedPlan {
                        ExtractedPlanCard(plan: extracted, onCode: {
                            sendQuickAction("Nu vill jag börja koda projektet. Gå igenom fas 1 steg för steg och ge mig konkreta, körbara kodinstruktioner.")
                        })
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .id("plan-card")
                    }

                    ForEach(plan.messages) { msg in
                        PureChatBubble(message: msg)
                            .id(msg.id)
                    }

                    if manager.isStreaming {
                        StreamingBubble(text: manager.streamingText)
                            .id("streaming")
                            .transition(.opacity)
                    }

                    // Bottom anchor
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                planInputSection
            }
            // New messages — scroll with animation
            .onChange(of: plan.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            // Streaming — throttled to every ~80 chars (no animation = smooth)
            .onChange(of: manager.streamingText.count / 80) { _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Input section

    var planInputSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.12)

            VStack(spacing: 8) {
                // Quick-action chips
                if plan != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            PlanChip("Koda projektet", icon: "hammer.fill", accent: true) {
                                sendQuickAction("Nu vill jag börja koda projektet. Gå igenom fas 1 steg för steg och ge mig konkreta, körbara kodinstruktioner.")
                            }
                            PlanChip("Förfina planen", icon: "pencil") {
                                sendQuickAction("Kan du förfina och förbättra planen? Finns det något viktigt vi missat?")
                            }
                            PlanChip("Tidsplan", icon: "calendar") {
                                sendQuickAction("Kan du skapa en detaljerad tidsplan med milstolpar och deadlines?")
                            }
                            PlanChip("Risker", icon: "exclamationmark.triangle") {
                                sendQuickAction("Vilka är de största riskerna med projektet och hur hanterar vi dem?")
                            }
                            PlanChip("MVP", icon: "smallcircle.filled.circle") {
                                sendQuickAction("Vad är den absoluta MVP:n för projektet? Vad kan vi lansera snabbast?")
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Input pill
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Beskriv din idé eller ställ en fråga...", text: $inputText, axis: .vertical)
                        .focused($inputFocused)
                        .lineLimit(1...6)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .padding(.leading, 4)
                        .padding(.vertical, 6)

                    // Send / Stop button
                    Button(action: manager.isStreaming ? stopStreaming : sendMessage) {
                        ZStack {
                            Circle()
                                .fill(
                                    manager.isStreaming
                                    ? Color.red.opacity(0.15)
                                    : (inputText.isBlank ? Color.clear : Color.white)
                                )
                                .frame(width: 32, height: 32)
                            Image(systemName: manager.isStreaming ? "stop.fill" : "arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(
                                    manager.isStreaming ? .red
                                    : (inputText.isBlank ? .secondary.opacity(0.3) : .black)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isBlank && !manager.isStreaming)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.inputBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(Color.inputBorder, lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            .padding(.top, 8)
        }
        .background(Color.chatBackground)
    }

    // MARK: - Empty state

    var planEmptyState: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)

                    VStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.accentNavi.opacity(0.1))
                                .frame(width: 76, height: 76)
                            Image(systemName: "map")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.accentNavi)
                        }
                        Text("Planera ett projekt")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Beskriv din idé och Claude hjälper dig planera\narkitektur, faser och nästa steg.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(planSuggestions, id: \.self) { suggestion in
                            Button {
                                _ = manager.newPlan()
                                inputText = suggestion
                                sendMessage()
                            } label: {
                                Text(suggestion)
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.07), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 460)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 32)
            }
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = false }

            planInputSection
        }
    }

    private let planSuggestions = [
        "iOS-app för att spåra träning",
        "REST API i Swift med Vapor",
        "macOS-app för anteckningar",
        "Full-stack webbapp med SwiftUI + Vapor"
    ]

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.isBlank else { return }
        if manager.activePlan == nil { _ = manager.newPlan() }
        guard var plan = manager.activePlan else { return }

        let text = inputText
        inputText = ""

        sendTask?.cancel()
        sendTask = Task {
            try? await manager.send(text: text, in: &plan) { _ in }
            manager.activePlan = plan
            if let idx = manager.plans.firstIndex(where: { $0.id == plan.id }) {
                manager.plans[idx] = plan
            }
        }
    }

    private func sendQuickAction(_ text: String) {
        if manager.activePlan == nil { _ = manager.newPlan() }
        inputText = text
        sendMessage()
    }

    private func stopStreaming() {
        sendTask?.cancel()
        sendTask = nil
        manager.isStreaming = false
        manager.streamingText = ""
    }
}

// MARK: - Plan quick-action chip

struct PlanChip: View {
    let label: String
    let icon: String
    var accent: Bool = false
    let action: () -> Void

    init(_ label: String, icon: String, accent: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.accent = accent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: accent ? .semibold : .regular))
                Text(label)
                    .font(.system(size: 12, weight: accent ? .semibold : .medium))
            }
            .foregroundColor(accent ? .accentNavi : .primary.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                accent
                ? Color.accentNavi.opacity(0.1)
                : Color.white.opacity(0.05)
            )
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        accent ? Color.accentNavi.opacity(0.25) : Color.white.opacity(0.07),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ExtractedPlanCard
// Shows the structured plan extracted from the conversation as a collapsible card.

struct ExtractedPlanCard: View {
    let plan: ExtractedPlan
    var onCode: (() -> Void)? = nil
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.accentNavi)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.projectName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(plan.description)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(isExpanded ? nil : 1)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().opacity(0.1)

                VStack(alignment: .leading, spacing: 12) {
                    // Tech stack
                    if !plan.techStack.isEmpty {
                        planSection("Teknisk stack", icon: "cpu") {
                            FlowLayout(spacing: 6) {
                                ForEach(plan.techStack, id: \.self) { tech in
                                    Text(tech)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.accentNavi)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Color.accentNavi.opacity(0.1))
                                        .cornerRadius(5)
                                }
                            }
                        }
                    }

                    // Phases
                    if !plan.phases.isEmpty {
                        planSection("Faser", icon: "list.number") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(plan.phases) { phase in
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(Color.accentNavi.opacity(0.5))
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 5)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(phase.name)
                                                    .font(.system(size: 12, weight: .semibold))
                                                if let days = phase.estimatedDays {
                                                    Text("~\(days) dagar")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.secondary)
                                                        .padding(.horizontal, 6).padding(.vertical, 1)
                                                        .background(Color.white.opacity(0.05))
                                                        .cornerRadius(4)
                                                }
                                            }
                                            Text(phase.description)
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Key features
                    if !plan.keyFeatures.isEmpty {
                        planSection("Nyckelfunktioner", icon: "star") {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(plan.keyFeatures, id: \.self) { feature in
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.green)
                                        Text(feature)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Time estimate
                    if !plan.estimatedTime.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(plan.estimatedTime)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Next step
                    if !plan.nextStep.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.accentNavi)
                            Text("**Nästa steg:** \(plan.nextStep)")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                        .padding(10)
                        .background(Color.accentNavi.opacity(0.07))
                        .cornerRadius(8)
                    }

                    // "Koda projektet" button
                    if let onCode {
                        Button(action: onCode) {
                            HStack(spacing: 6) {
                                Image(systemName: "hammer.fill")
                                    .font(.system(size: 12))
                                Text("Koda projektet")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.accentNavi.opacity(0.15))
                            .foregroundColor(.accentNavi)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.accentNavi.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color.white.opacity(0.04))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentNavi.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func planSection<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            content()
        }
    }
}

// MARK: - FlowLayout (wrapping HStack)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Previews

#Preview("PlanView") {
    PlanView()
        #if os(macOS)
        .frame(width: 700, height: 600)
        #endif
}

#Preview("ExtractedPlanCard") {
    let plan = ExtractedPlan(
        projectName: "TrackFit iOS",
        description: "En iOS-app för att spåra träning och hälsa",
        techStack: ["Swift", "SwiftUI", "HealthKit", "CoreData"],
        phases: [
            PlanPhase(name: "Fas 1: Grundstruktur", description: "Sätt upp projekt och datamodeller",
                      tasks: ["Xcode-projekt", "Datamodeller"], estimatedDays: 3),
            PlanPhase(name: "Fas 2: UI", description: "Bygg gränssnittet",
                      tasks: ["Dashboard", "Träningslogg"], estimatedDays: 5)
        ],
        estimatedTime: "3-4 veckor",
        keyFeatures: ["Träningslogg", "HealthKit-integration", "Statistik"],
        risks: ["HealthKit-behörigheter kan vara komplicerade"],
        nextStep: "Skapa Xcode-projektet och definiera datamodellerna"
    )
    return ExtractedPlanCard(plan: plan, onCode: {})
        .padding()
        .background(Color.black)
}

#Preview("PlanChips") {
    HStack(spacing: 8) {
        PlanChip("Koda projektet", icon: "hammer.fill", accent: true) {}
        PlanChip("Förfina planen", icon: "pencil") {}
        PlanChip("Tidsplan", icon: "calendar") {}
    }
    .padding()
    .background(Color.black)
}
