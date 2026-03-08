import Foundation
import Combine

struct DeviceStatus: Codable {
    var deviceID: String
    var deviceName: String
    var isMac: Bool
    var isOnline: Bool
    var agentRunning: Bool
    var agentStatus: String
    var currentTask: String
    var currentStep: Int
    var totalSteps: Int
    var lastUpdate: Date
    var appVersion: String

    init() {
        deviceID = UIDevice.deviceID
        deviceName = UIDevice.deviceName
        isMac = UIDevice.isMac
        isOnline = true
        agentRunning = false
        agentStatus = ""
        currentTask = ""
        currentStep = 0
        totalSteps = 0
        lastUpdate = Date()
        appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

@MainActor
final class DeviceStatusBroadcaster: ObservableObject {
    static let shared = DeviceStatusBroadcaster()

    @Published var localStatus = DeviceStatus()
    @Published var remoteStatus: DeviceStatus?
    @Published var remoteMacIsOnline = false
    @Published var connectionMethod: ConnectionMethod = .none

    enum ConnectionMethod: String {
        case localHTTP = "LAN"
        case bonjour = "Bonjour"
        case iCloud = "iCloud"
        case none = "Frånkopplad"
    }

    private let sync = iCloudSyncEngine.shared
    private var broadcastTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var signalQuery: NSMetadataQuery?
    private var lastBroadcast = Date.distantPast

    private var statusURL: URL? {
        sync.deviceStatusRoot?.appendingPathComponent("\(UIDevice.deviceID).json")
    }

    private var signalFileURL: URL? {
        sync.naviRoot?.appendingPathComponent("device-signal.json")
    }

    private init() {
        startBroadcasting()
        startWatching()
        startSignalMonitoring()

        #if os(iOS)
        Task {
            LocalNetworkClient.shared.startAutoDiscovery()
            PeerSyncEngine.shared.startBrowsing()
        }
        #endif
    }

    // MARK: - Broadcast our status

    func startBroadcasting() {
        broadcastTask?.cancel()
        broadcastTask = Task {
            while !Task.isCancelled {
                await broadcast()
                let interval = localStatus.agentRunning ? 8.0 : 20.0
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func broadcast() async {
        var status = localStatus
        status.agentRunning = AgentEngine.shared.isRunning
        status.agentStatus = AgentEngine.shared.statusMessage
        status.lastUpdate = Date()
        localStatus = status

        guard let url = statusURL else { return }
        do {
            try await sync.write(status, to: url)
        } catch {
            NaviLog.error("DeviceStatus: kunde inte broadcast", error: error)
        }

        await writeSignal()
    }

    func update(task: String, step: Int, total: Int) {
        localStatus.currentTask = task
        localStatus.currentStep = step
        localStatus.totalSteps = total
        let now = Date()
        if now.timeIntervalSince(lastBroadcast) > 3 {
            lastBroadcast = now
            Task { await broadcast() }
        }
    }

    // MARK: - Signal file (fast cross-device notification)

    private func writeSignal() async {
        guard let url = signalFileURL else { return }
        let signal: [String: String] = [
            "deviceID": UIDevice.deviceID,
            "timestamp": Date().iso8601
        ]
        if let data = try? JSONSerialization.data(withJSONObject: signal) {
            try? await sync.writeData(data, to: url)
        }
    }

    private func startSignalMonitoring() {
        guard let root = sync.naviRoot else { return }
        let signalPath = root.appendingPathComponent("device-signal.json").path

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@",
                                      NSMetadataItemPathKey, signalPath)
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchRemoteStatus()
            }
        }
        query.start()
        signalQuery = query
    }

    // MARK: - Watch remote status

    func startWatching() {
        watchTask?.cancel()
        watchTask = Task {
            while !Task.isCancelled {
                await fetchRemoteStatus()
                await detectConnectionMethod()
                let interval = remoteMacIsOnline ? 8.0 : 15.0
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func fetchRemoteStatus() async {
        guard let dir = sync.deviceStatusRoot,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        let myID = UIDevice.deviceID

        var foundRemoteMac = false
        for file in jsonFiles {
            guard let status = try? await sync.read(DeviceStatus.self, from: file),
                  status.deviceID != myID
            else { continue }

            remoteStatus = status
            let age = Date().timeIntervalSince(status.lastUpdate)
            if status.isMac && age < 45 {
                remoteMacIsOnline = true
                foundRemoteMac = true
            }
        }

        if !foundRemoteMac {
            if let remote = remoteStatus, remote.isMac {
                remoteMacIsOnline = Date().timeIntervalSince(remote.lastUpdate) < 90
            } else {
                remoteMacIsOnline = false
            }
        }
    }

    private func detectConnectionMethod() async {
        #if os(iOS)
        let client = LocalNetworkClient.shared
        if let saved = URL(string: SettingsStore.shared.macServerURL),
           !SettingsStore.shared.macServerURL.isEmpty,
           await client.pingQuick(saved) {
            connectionMethod = .localHTTP
        } else if !PeerSyncEngine.shared.connections.isEmpty {
            connectionMethod = .bonjour
        } else if remoteMacIsOnline {
            connectionMethod = .iCloud
        } else {
            connectionMethod = .none
        }
        #else
        connectionMethod = LocalNetworkServer.shared.isRunning ? .localHTTP : .iCloud
        #endif
    }

    func stopAll() {
        broadcastTask?.cancel()
        watchTask?.cancel()
        broadcastTask = nil
        watchTask = nil
        signalQuery?.stop()
        signalQuery = nil
        #if os(iOS)
        LocalNetworkClient.shared.stopAutoDiscovery()
        PeerSyncEngine.shared.stopBrowsing()
        #endif
    }
}
