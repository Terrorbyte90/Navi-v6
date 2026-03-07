import SwiftUI

// MARK: - PlanView
// Main planning view — chat with Claude to plan a new project, with structured plan extraction.

struct PlanView: View {
    @StateObject private var manager = PlanManager.shared
    @State private var inputText = ""
    @State private var selectedImages: [Data] = []
    @State private var showStructuredPlan = false

    var plan: ProjectPlan? { manager.activePlan }

    var body: some View {
        VStack(spacing: 0) {
            planTopBar

            Divider().opacity(0.15)

            if let plan {
                ZStack(alignment: .trailing) {
                    // Main chat
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                // Structured plan card (if extracted)
                                if let extracted = plan.extractedPlan {
                                    ExtractedPlanCard(plan: extracted)
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .id("plan-card")
                                }

                                ForEach(plan.messages) { msg in
                                    PureChatBubble(message: msg)
                                        .id(msg.id)
                                }

                                if manager.isStreaming {
                                    StreamingBubble(text: manager.streamingText)
                                        .id("streaming")
                                }
                            }
                            .padding()
                            .contentShape(Rectangle())
                            .onTapGesture { dismissKeyboard() }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            VStack(spacing: 0) {
                                Divider().opacity(0.15)
                                planInputBar
                            }
                            .background(Color.chatBackground)
                        }
                        .onChange(of: plan.messages.count) { _ in scrollToBottom(proxy, plan: plan) }
                        .onChange(of: manager.streamingText) { _ in scrollToBottom(proxy, plan: plan) }
                    }
                }
            } else {
                planEmptyState
            }
        }
        .background(Color.chatBackground)
        .onAppear {
            if manager.activePlan == nil && !manager.plans.isEmpty {
                manager.activePlan = manager.plans.first
            }
        }
    }

    // MARK: - Top bar

    var planTopBar: some View {
        HStack(spacing: 12) {
            // Status + model picker
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
                    HStack(spacing: 5) {
                        Image(systemName: plan.status.icon)
                            .font(.system(size: 11))
                        Text(plan.status.rawValue)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
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
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 11))
                        Text(plan.model.displayName)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Show/hide structured plan toggle
            if plan?.extractedPlan != nil {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        showStructuredPlan.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 11))
                        Text("Planöversikt")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.accentEon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentEon.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }

            // Cost
            let sessionCost = CostTracker.shared.sessionSEK
            if sessionCost > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(String(format: "%.3f kr", sessionCost))
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Empty state

    var planEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 52))
                    .foregroundColor(.accentEon.opacity(0.5))
                Text("Planera ett projekt")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("Beskriv din idé och Claude hjälper dig planera\narkitektur, faser och nästa steg.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Suggestion chips
            VStack(spacing: 8) {
                Text("Kom igång med ett förslag:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

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
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 460)
            }

            GlassButton("Starta ny plan", icon: "plus", isPrimary: true) {
                _ = manager.newPlan()
            }

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider().opacity(0.15)
                planInputBar
            }
            .background(Color.chatBackground)
        }
    }

    private let planSuggestions = [
        "Jag vill bygga en iOS-app för att spåra träning",
        "Hjälp mig planera ett REST API i Swift",
        "Jag vill skapa en macOS-app för anteckningar",
        "Planera en full-stack webbapp med SwiftUI + Vapor"
    ]

    // MARK: - Input bar

    var planInputBar: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("Beskriv din idé eller ställ en fråga...", text: $inputText, axis: .vertical)
                .lineLimit(1...8)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .onSubmit { sendMessage() }
                .padding(.leading, 12)
                .padding(.vertical, 8)

            Button(action: sendMessage) {
                if manager.isStreaming {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(inputText.isBlank ? .secondary.opacity(0.3) : .black)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(inputText.isBlank ? Color.clear : Color.white)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(inputText.isBlank && !manager.isStreaming)
            .padding(.trailing, 4)
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.inputBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Color.inputBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Send

    private func sendMessage() {
        guard !inputText.isBlank else { return }
        if manager.activePlan == nil {
            _ = manager.newPlan()
        }
        guard var plan = manager.activePlan else { return }

        let text = inputText
        inputText = ""

        Task {
            try? await manager.send(text: text, in: &plan) { _ in }
            await MainActor.run {
                manager.activePlan = plan
                if let idx = manager.plans.firstIndex(where: { $0.id == plan.id }) {
                    manager.plans[idx] = plan
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, plan: ProjectPlan) {
        if manager.isStreaming {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let last = plan.messages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

// MARK: - ExtractedPlanCard
// Shows the structured plan extracted from the conversation as a collapsible card.

struct ExtractedPlanCard: View {
    let plan: ExtractedPlan
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accentEon)
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
                Divider().opacity(0.12)

                VStack(alignment: .leading, spacing: 12) {
                    // Tech stack
                    if !plan.techStack.isEmpty {
                        planSection("Teknisk stack", icon: "cpu") {
                            FlowLayout(spacing: 6) {
                                ForEach(plan.techStack, id: \.self) { tech in
                                    Text(tech)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.accentEon)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.accentEon.opacity(0.1))
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
                                            .fill(Color.accentEon.opacity(0.6))
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
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 1)
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

                    // Time + next step
                    HStack(spacing: 16) {
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
                        Spacer()
                    }

                    if !plan.nextStep.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.accentEon)
                            Text("**Nästa steg:** \(plan.nextStep)")
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                        .padding(10)
                        .background(Color.accentEon.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.accentEon.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func planSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
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

// MARK: - Preview

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
            PlanPhase(name: "Fas 1: Grundstruktur", description: "Sätt upp projekt och datamodeller", tasks: ["Xcode-projekt", "Datamodeller"], estimatedDays: 3),
            PlanPhase(name: "Fas 2: UI", description: "Bygg gränssnittet", tasks: ["Dashboard", "Träningslogg"], estimatedDays: 5)
        ],
        estimatedTime: "3-4 veckor",
        keyFeatures: ["Träningslogg", "HealthKit-integration", "Statistik"],
        risks: ["HealthKit-behörigheter kan vara komplicerade"],
        nextStep: "Skapa Xcode-projektet och definiera datamodellerna"
    )
    return ExtractedPlanCard(plan: plan)
        .padding()
        .background(Color.black)
}
