#if os(iOS)
import Foundation
import Network

@MainActor
final class OfflineManager: ObservableObject {
    static let shared = OfflineManager()

    @Published var isOnline = true
    @Published var iCloudAvailable = false
    @Published var macReachable = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.navi.networkmonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    await self?.checkMacReachability()
                } else {
                    self?.macReachable = false
                }
            }
        }
        monitor.start(queue: queue)

        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil

        Task { await checkMacReachability() }
    }

    func checkMacReachability() async {
        // Try saved URL first
        if !SettingsStore.shared.macServerURL.isEmpty,
           let url = URL(string: SettingsStore.shared.macServerURL) {
            LocalNetworkClient.shared.setMacAddress(url)
            if (try? await LocalNetworkClient.shared.fetchStatus()) != nil {
                macReachable = true
                return
            }
        }

        // Auto-discover Mac if saved URL failed or is missing
        if let url = await LocalNetworkClient.shared.discoverMac() {
            LocalNetworkClient.shared.setMacAddress(url)
            macReachable = true
        } else {
            macReachable = false
        }
    }

    var syncMethod: SyncMethod {
        if macReachable { return .localHTTP }
        if PeerSyncEngine.shared.connectedPeer != nil { return .bonjour }
        if iCloudAvailable { return .iCloud }
        return .offline
    }

    enum SyncMethod {
        case iCloud, localHTTP, bonjour, offline

        var description: String {
            switch self {
            case .iCloud: return "iCloud"
            case .localHTTP: return "Lokalt nätverk"
            case .bonjour: return "Bonjour"
            case .offline: return "Offline"
            }
        }
    }
}
#endif
