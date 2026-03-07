#if os(macOS)
import Foundation
import Combine

// Background daemon that processes instruction queue when app is running.
// Starts all three sync channels: iCloud, Bonjour P2P, and local HTTP server.
@MainActor
final class BackgroundDaemon: ObservableObject {
    static let shared = BackgroundDaemon()

    @Published var isActive = false
    @Published var processedCount = 0
    @Published var lastActivity: Date?

    private var pollingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        guard !isActive else { return }
        isActive = true

        // Channel 1: iCloud sync + instruction processing
        InstructionQueue.shared.startProcessingLoop()

        // Channel 2: Local HTTP server (auto-publishes IP to iCloud for iOS discovery)
        LocalNetworkServer.shared.start()

        // Channel 3: Bonjour P2P advertising (iOS browses for this)
        PeerSyncEngine.shared.startAdvertising()

        // Status broadcasting (every 5s to iCloud)
        DeviceStatusBroadcaster.shared.startBroadcasting()

        startPolling()
    }

    func stop() {
        isActive = false
        pollingTask?.cancel()
        pollingTask = nil
        InstructionQueue.shared.stopProcessingLoop()
        LocalNetworkServer.shared.stop()
        PeerSyncEngine.shared.stopAdvertising()
        DeviceStatusBroadcaster.shared.stopAll()
    }

    private func startPolling() {
        pollingTask = Task {
            var tickCount = 0
            while !Task.isCancelled && isActive {
                await tick(tickCount: tickCount)
                tickCount += 1
                try? await Task.sleep(seconds: 10.0)
            }
        }
    }

    private func tick(tickCount: Int) async {
        await DeviceStatusBroadcaster.shared.broadcast()
        processedCount += 1
        lastActivity = Date()

        if tickCount % 3 == 0 {
            await refreshServerURL()
        }
    }

    private func refreshServerURL() async {
        let server = LocalNetworkServer.shared
        guard server.isRunning, server.serverURL != nil else { return }
        let info: [String: String] = [
            "url": server.serverURL!.absoluteString,
            "deviceName": UIDevice.deviceName,
            "timestamp": Date().iso8601
        ]
        guard let root = iCloudSyncEngine.shared.eonCodeRoot,
              let data = try? JSONSerialization.data(withJSONObject: info)
        else { return }
        let macInfoURL = root.appendingPathComponent("mac-server.json")
        try? await iCloudSyncEngine.shared.writeData(data, to: macInfoURL)
    }
}
#endif
