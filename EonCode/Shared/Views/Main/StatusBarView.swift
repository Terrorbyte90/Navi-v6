import SwiftUI

struct StatusBarView: View {
    @StateObject private var store = ProjectStore.shared
    @StateObject private var broadcaster = DeviceStatusBroadcaster.shared
    @StateObject private var settings = SettingsStore.shared

    var activeAgent: ProjectAgent? {
        guard let p = store.activeProject else { return nil }
        return AgentPool.shared.agents[p.id]
    }

    var body: some View {
        HStack(spacing: 16) {
            // Model picker
            if let project = store.activeProject {
                ModelPickerCompact(project: project)
            }

            Divider()
                .frame(height: 16)
                .opacity(0.3)

            // Mac/iOS status indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 7, height: 7)
                Text(connectionText)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Remote status (iOS shows mac status, Mac shows nothing extra)
            if let remote = broadcaster.remoteStatus, broadcaster.remoteMacIsOnline {
                HStack(spacing: 4) {
                    if remote.agentRunning {
                        SpinningGearIcon()
                    }
                    Text(remote.agentStatus.prefix(40))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    var connectionColor: Color {
        #if os(macOS)
        return .green
        #else
        return broadcaster.remoteMacIsOnline ? .green : .orange
        #endif
    }

    var connectionText: String {
        #if os(macOS)
        return "Mac ●"
        #else
        return broadcaster.remoteMacIsOnline ? "Mac online" : "Mac offline"
        #endif
    }
}

// MARK: - Previews

#Preview("StatusBarView") {
    StatusBarView()
        .padding()
        .background(Color.black)
}

// MARK: - Compact model picker (for toolbar)

struct ModelPickerCompact: View {
    let project: NaviProject
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(project.activeModel.displayName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker) {
            ModelPickerView(currentModel: project.activeModel) { model in
                var updated = project
                updated.activeModel = model
                Task { await ProjectStore.shared.save(updated) }
                showPicker = false
            }
            .padding()
            .frame(width: 280)
        }
    }
}

struct SpinningGearIcon: View {
    var size: CGFloat = 10
    var systemName: String = "gearshape.fill"
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundColor(.accentNavi)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
