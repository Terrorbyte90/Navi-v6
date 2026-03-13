import SwiftUI

// MARK: - SamtalView
// Main Calls view — Idag / Historik / Schemalägg / Live

enum SamtalTab: String, CaseIterable {
    case idag       = "Idag"
    case historik   = "Historik"
    case schema     = "Schemalägg"
    case live       = "Live"

    var icon: String {
        switch self {
        case .idag:     return "chart.bar.fill"
        case .historik: return "clock.fill"
        case .schema:   return "calendar.badge.plus"
        case .live:     return "antenna.radiowaves.left.and.right"
        }
    }
}

struct SamtalView: View {
    @StateObject private var service = CallsService.shared
    @State private var selectedTab: SamtalTab = .idag
    @State private var setupError: String?
    @State private var isSettingUp = false

    var body: some View {
        VStack(spacing: 0) {
            samtalTabBar

            Group {
                switch selectedTab {
                case .idag:     IdagView()
                case .historik: HistorikView()
                case .schema:   SchemaView()
                case .live:     LiveView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.chatBackground)
        .onAppear {
            Task {
                await service.refreshAll()
                service.startLivePolling()
                service.startStatsPolling()
            }
        }
        .onDisappear {
            service.stopLivePolling()
        }
    }

    // MARK: - Tab bar

    var samtalTabBar: some View {
        HStack(spacing: 0) {
            ForEach(SamtalTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundColor(selectedTab == tab ? .accentNavi : .secondary.opacity(0.6))
                    .overlay(
                        Rectangle()
                            .fill(Color.accentNavi)
                            .frame(height: 2)
                            .opacity(selectedTab == tab ? 1 : 0),
                        alignment: .bottom
                    )
                }
                .buttonStyle(.plain)
            }

            // Setup button
            setupButton
                .frame(width: 40)
                .padding(.vertical, 8)
        }
        .background(Color.chatBackground)
        .overlay(Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    var setupButton: some View {
        Button {
            Task {
                isSettingUp = true
                await service.setupTelephony()
                isSettingUp = false
                if let err = service.lastError { setupError = err }
            }
        } label: {
            if isSettingUp {
                ProgressView().scaleEffect(0.7)
            } else {
                Image(systemName: service.isConfigured ? "checkmark.circle.fill" : "gear")
                    .foregroundColor(service.isConfigured ? .green : .secondary)
            }
        }
        .alert("Setup-fel", isPresented: Binding(get: { setupError != nil }, set: { if !$0 { setupError = nil } })) {
            Button("OK") { setupError = nil }
        } message: {
            Text(setupError ?? "")
        }
    }
}

// MARK: - Idag (Today stats + live calls)

struct IdagView: View {
    @StateObject private var service = CallsService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let stats = service.stats {
                    statsGrid(stats.today)
                    Divider().opacity(0.1)
                } else if service.isLoading {
                    ProgressView("Laddar statistik…")
                        .padding()
                }

                if !service.liveCalls.isEmpty {
                    liveSectionHeader
                    ForEach(service.liveCalls) { call in
                        LiveCallCard(call: call)
                            .padding(.horizontal, 16)
                    }
                }

                if let err = service.lastError {
                    errorBanner(err)
                }

                if !service.isConfigured {
                    configurationBanner
                }
            }
            .padding(.vertical, 16)
        }
        .refreshable { await service.refreshAll() }
    }

    func statsGrid(_ s: DayStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IDAG")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatCell(label: "Totalt",    value: "\(s.total)",          icon: "phone",                    color: .secondary)
                StatCell(label: "Inkommande", value: "\(s.incoming)",      icon: "phone.arrow.down.left",    color: .blue)
                StatCell(label: "Utgående",  value: "\(s.outbound)",       icon: "phone.arrow.up.right",     color: .purple)
                StatCell(label: "Pågående",  value: "\(s.active)",         icon: "antenna.radiowaves.left.and.right", color: .green)
                StatCell(label: "Avslutade", value: "\(s.completed)",      icon: "checkmark.circle",         color: .gray)
                StatCell(label: "Mål uppnådda", value: "\(s.goalsAchieved)", icon: "target",                color: .orange)
            }
            .padding(.horizontal, 16)

            if s.avgDurationSec > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Snitt samtalstid: \(s.avgDurationSec / 60)m \(s.avgDurationSec % 60)s")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    var liveSectionHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().stroke(Color.green.opacity(0.4), lineWidth: 4)
                        .scaleEffect(1.4)
                )
            Text("PÅGÅENDE SAMTAL (\(service.liveCalls.count))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(msg).font(.system(size: 12)).foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }

    var configurationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "gear.badge.questionmark").foregroundColor(.orange)
                Text("Telefoni ej konfigurerat")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("Tryck på ⚙️ uppe till höger för att sätta upp 46elks + ElevenLabs.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

struct StatCell: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color.opacity(0.8))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
    }
}

// MARK: - Live call card (compact, used on Idag tab)

struct LiveCallCard: View {
    let call: Call

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: call.direction == .incoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(call.direction == .incoming ? (call.from ?? "Okänt") : (call.to ?? "Okänt"))
                    .font(.system(size: 14, weight: .medium))
                if let goal = call.goal {
                    Text(goal)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(call.status.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(naviHex: call.status.color))
                Text(call.durationFormatted)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
    }
}

// MARK: - Historik (Call history)

struct HistorikView: View {
    @StateObject private var service = CallsService.shared
    @State private var selectedCall: Call?

    var body: some View {
        Group {
            if service.calls.isEmpty && !service.isLoading {
                emptyState
            } else {
                callList
            }
        }
        .refreshable { await service.fetchCalls() }
        .sheet(item: $selectedCall) { call in
            CallDetailSheet(call: call)
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.slash")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.2))
            Text("Inga samtal ännu")
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var callList: some View {
        List {
            ForEach(service.calls) { call in
                CallRow(call: call)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedCall = call }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }
}

struct CallRow: View {
    let call: Call

    var body: some View {
        HStack(spacing: 12) {
            // Direction icon
            ZStack {
                Circle()
                    .fill(directionColor.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: call.direction?.icon ?? "phone")
                    .font(.system(size: 14))
                    .foregroundColor(directionColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(phoneNumber)
                    .font(.system(size: 14, weight: .medium))
                HStack(spacing: 6) {
                    Text(call.direction?.label ?? "—")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                    if let goal = call.goal {
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.3))
                        Text(goal)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if !call.goalResultLabel.isEmpty {
                    Text(call.goalResultLabel)
                        .font(.system(size: 11))
                }
                Text(call.durationFormatted)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                if let date = call.startDate {
                    Text(DateFormatter.displayDate.string(from: date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(12)
    }

    var phoneNumber: String {
        call.direction == .incoming ? (call.from ?? "Okänt nummer") : (call.to ?? "Okänt nummer")
    }

    var directionColor: Color {
        switch call.direction {
        case .incoming: return .blue
        case .outbound: return .purple
        default:        return .secondary
        }
    }
}

// MARK: - Call detail sheet

struct CallDetailSheet: View {
    let call: Call
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header info
                    callHeader

                    // Summary
                    if let summary = call.summary ?? call.analysis?.transcript_summary {
                        sectionCard(title: "Sammanfattning", icon: "doc.text") {
                            Text(summary)
                                .font(.system(size: 14))
                                .foregroundColor(.primary.opacity(0.85))
                        }
                    }

                    // Goal result
                    if let goalResult = call.goalResult, !goalResult.isEmpty {
                        sectionCard(title: "Mål", icon: "target") {
                            HStack(spacing: 8) {
                                Text(call.goalResultLabel)
                                    .font(.system(size: 14, weight: .medium))
                                if let goal = call.goal {
                                    Text("—")
                                    Text(goal)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Transcript
                    if let lines = call.transcript ?? call.liveTranscript, !lines.isEmpty {
                        sectionCard(title: "Transkript", icon: "text.bubble") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(lines) { line in
                                    TranscriptLineView(line: line)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(callTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
            #endif
        }
        .background(Color.chatBackground)
    }

    var callTitle: String {
        let number = call.direction == .incoming ? (call.from ?? "Okänt") : (call.to ?? "Okänt")
        return "\(call.direction?.label ?? "Samtal") — \(number)"
    }

    var callHeader: some View {
        HStack(spacing: 16) {
            // Status indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(naviHex: call.status.color))
                    .frame(width: 12, height: 12)
                Text(call.status.label)
                    .font(.system(size: 10))
                    .foregroundColor(Color(naviHex: call.status.color))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(callTitle)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    if let start = call.startDate {
                        Label(DateFormatter.displayDate.string(from: start), systemImage: "calendar")
                    }
                    Label(call.durationFormatted, systemImage: "timer")
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.6))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(12)
    }

    func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(12)
    }
}

struct TranscriptLineView: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(line.isAgent ? "AI" : "👤")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(line.isAgent ? .accentNavi : .secondary)
                .frame(width: 24, alignment: .leading)

            Text(line.text)
                .font(.system(size: 13))
                .foregroundColor(line.isAgent ? .primary : .primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Text(String(format: "%.0fs", line.timeSec))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Schemalägg (Schedule outbound calls)

struct SchemaView: View {
    @StateObject private var service = CallsService.shared
    @State private var showAddForm = false
    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Add button
            HStack {
                Spacer()
                Button {
                    showAddForm = true
                } label: {
                    Label("Schemalägg samtal", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.accentNavi)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color.chatBackground)
            .overlay(Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1), alignment: .bottom)

            if service.scheduled.isEmpty {
                emptyState
            } else {
                scheduledList
            }
        }
        .sheet(isPresented: $showAddForm) {
            ScheduleCallForm()
        }
        .alert("Fel", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .refreshable { await service.fetchScheduled() }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.2))
            Text("Inga schemalagda samtal")
                .foregroundColor(.secondary.opacity(0.5))
            Text("Tryck + för att lägga till ett samtal")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var scheduledList: some View {
        List {
            ForEach(service.scheduled) { sc in
                ScheduledCallRow(call: sc)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                do { try await service.deleteScheduled(id: sc.id) }
                                catch { deleteError = error.localizedDescription }
                            }
                        } label: {
                            Label("Ta bort", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }
}

struct ScheduledCallRow: View {
    let call: ScheduledCall

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 38, height: 38)
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(call.to)
                    .font(.system(size: 14, weight: .medium))
                Text(call.goal)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(call.statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(statusColor)
                if let date = call.scheduledDate {
                    Text(scheduledTimeString(date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(12)
    }

    var statusColor: Color {
        switch call.status {
        case "pending":  return .orange
        case "placing":  return .blue
        case "placed":   return .green
        case "failed":   return .red
        default:         return .secondary
        }
    }

    var statusIcon: String {
        switch call.status {
        case "pending":  return "clock"
        case "placing":  return "phone.fill"
        case "placed":   return "checkmark.circle.fill"
        case "failed":   return "exclamationmark.circle.fill"
        default:         return "phone"
        }
    }

    func scheduledTimeString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Idag \(DateFormatter.displayTime.string(from: date))"
        } else if cal.isDateInTomorrow(date) {
            return "Imorgon \(DateFormatter.displayTime.string(from: date))"
        } else {
            return DateFormatter.displayDate.string(from: date)
        }
    }
}

// MARK: - Schedule Call Form

struct ScheduleCallForm: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CallsService.shared

    @State private var toNumber = ""
    @State private var goal = ""
    @State private var systemPrompt = ""
    @State private var firstMessage = ""
    @State private var notes = ""
    @State private var scheduledAt = Date().addingTimeInterval(3600)
    @State private var isSubmitting = false
    @State private var error: String?

    var canSubmit: Bool {
        !toNumber.trimmingCharacters(in: .whitespaces).isEmpty &&
        !goal.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Samtalsinformation") {
                    HStack {
                        Image(systemName: "phone.fill").foregroundColor(.secondary)
                        TextField("Telefonnummer (+46...)", text: $toNumber)
                            #if os(iOS)
                            .keyboardType(.phonePad)
                            #endif
                    }

                    HStack(alignment: .top) {
                        Image(systemName: "target").foregroundColor(.secondary)
                        TextField("Mål med samtalet", text: $goal, axis: .vertical)
                            .lineLimit(3)
                    }
                }

                Section("Schema") {
                    DatePicker(
                        "Tidpunkt",
                        selection: $scheduledAt,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Avancerat (valfritt)") {
                    HStack(alignment: .top) {
                        Image(systemName: "text.bubble").foregroundColor(.secondary)
                        TextField("Systemprompt (lämna tomt för auto)", text: $systemPrompt, axis: .vertical)
                            .lineLimit(4)
                    }

                    HStack(alignment: .top) {
                        Image(systemName: "quote.opening").foregroundColor(.secondary)
                        TextField("Första meddelande (lämna tomt för auto)", text: $firstMessage, axis: .vertical)
                            .lineLimit(3)
                    }

                    HStack(alignment: .top) {
                        Image(systemName: "note.text").foregroundColor(.secondary)
                        TextField("Anteckningar", text: $notes, axis: .vertical)
                            .lineLimit(2)
                    }
                }

                if let err = error {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                            Text(err).font(.system(size: 12)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Schemalägg samtal")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView().scaleEffect(0.7) }
                        else { Text("Schemalägg") }
                    }
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        do {
            try await service.scheduleCall(
                to: toNumber.trimmingCharacters(in: .whitespaces),
                goal: goal.trimmingCharacters(in: .whitespaces),
                systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                firstMessage: firstMessage.isEmpty ? nil : firstMessage,
                scheduledAt: scheduledAt,
                notes: notes
            )
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Live (Real-time active call)

struct LiveView: View {
    @StateObject private var service = CallsService.shared
    @State private var selectedCallID: String?

    var body: some View {
        Group {
            if service.liveCalls.isEmpty {
                noLiveCallsView
            } else if service.liveCalls.count == 1 {
                LiveCallDetailView(call: service.liveCalls[0])
            } else {
                multiCallPicker
            }
        }
    }

    var noLiveCallsView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.06))
                    .frame(width: 72, height: 72)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary.opacity(0.25))
            }
            Text("Inga aktiva samtal")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
            Text("Pågående samtal visas här i realtid")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var multiCallPicker: some View {
        VStack(spacing: 0) {
            Text("Välj samtal att övervaka")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding()

            ForEach(service.liveCalls) { call in
                let number = call.direction == .incoming ? (call.from ?? "—") : (call.to ?? "—")
                Button {
                    selectedCallID = call.id
                } label: {
                    HStack {
                        LiveCallCard(call: call)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }

            if let id = selectedCallID, let call = service.liveCalls.first(where: { $0.id == id }) {
                Divider().padding(.vertical, 8)
                LiveCallDetailView(call: call)
            }
        }
    }
}

// MARK: - Live call detail — real-time transcript + goal progress

struct LiveCallDetailView: View {
    let call: Call
    @StateObject private var service = CallsService.shared
    @State private var scrollProxy: ScrollViewProxy?

    // Fetch detailed call with live transcript
    @State private var liveCall: Call?

    var displayCall: Call { liveCall ?? call }
    var lines: [TranscriptLine] { displayCall.liveTranscript ?? displayCall.transcript ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            liveHeader
            Divider().opacity(0.1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        if lines.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Väntar på transkript…")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding(40)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(lines) { line in
                                    LiveTranscriptBubble(line: line)
                                        .id(line.id)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .onAppear { scrollProxy = proxy }
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let goal = displayCall.goal {
                goalProgressBar
            }
        }
        .task {
            await pollLiveTranscript()
        }
    }

    var liveHeader: some View {
        HStack(spacing: 12) {
            // Animated live indicator
            LivePulse()

            VStack(alignment: .leading, spacing: 2) {
                let number = displayCall.direction == .incoming ? (displayCall.from ?? "Okänt") : (displayCall.to ?? "Okänt")
                Text(number)
                    .font(.system(size: 15, weight: .semibold))
                Text("\(displayCall.direction?.label ?? "Samtal") · \(displayCall.durationFormatted)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            Text(displayCall.status.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(naviHex: displayCall.status.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(naviHex: displayCall.status.color).opacity(0.12))
                .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var goalProgressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.1)
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(displayCall.goal ?? "")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
                Spacer()
                if !displayCall.goalResultLabel.isEmpty {
                    Text(displayCall.goalResultLabel)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
        }
    }

    private func pollLiveTranscript() async {
        while !Task.isCancelled {
            if let updated = await service.fetchCall(call.id) {
                liveCall = updated
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}

struct LiveTranscriptBubble: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if line.isAgent {
                Spacer(minLength: 40)
                agentBubble
            } else {
                customerBubble
                Spacer(minLength: 40)
            }
        }
        .padding(.vertical, 3)
    }

    var agentBubble: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("AI")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.accentNavi.opacity(0.6))
            Text(line.text)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentNavi.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    var customerBubble: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Kund")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
            Text(line.text)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Live pulse animation

struct LivePulse: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.2))
                .frame(width: 32, height: 32)
                .scaleEffect(pulsing ? 1.3 : 1.0)
                .opacity(pulsing ? 0 : 0.5)

            Circle()
                .fill(Color.green)
                .frame(width: 16, height: 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                pulsing = true
            }
        }
    }
}

