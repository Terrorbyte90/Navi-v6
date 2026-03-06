import Foundation
import Network

// MARK: - Local HTTP server (tertiary sync method)
// Mac runs server on port 52731, iOS connects via HTTP.
// The server also advertises itself via Bonjour (_navi-http._tcp) so iOS
// can auto-discover the Mac's IP without any manual configuration.

@MainActor
final class LocalNetworkServer: ObservableObject {
    static let shared = LocalNetworkServer()

    @Published var isRunning = false
    @Published var serverURL: URL?
    @Published var connectedClients: [String] = []

    private var listener: NWListener?
    private let port: NWEndpoint.Port = NWEndpoint.Port(rawValue: Constants.Sync.localHTTPPort)!

    private init() {}

    // MARK: - Start server (Mac only)

    func start() {
        #if os(macOS)
        listener?.cancel()
        listener = nil

        let params = NWParameters.tcp
        guard let listener = try? NWListener(using: params, on: port) else { return }

        // Advertise via Bonjour so iOS can auto-discover us
        listener.service = NWListener.Service(
            name: UIDevice.deviceName,
            type: Constants.Sync.httpServiceType
        )

        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    // Resolve and publish our local IP so iOS can connect
                    let ip = self?.localIPAddress() ?? "localhost"
                    self?.serverURL = URL(string: "http://\(ip):\(Constants.Sync.localHTTPPort)")
                    // Also write our URL to iCloud so iOS can find us even without Bonjour
                    await self?.publishURLToiCloud()
                case .failed:
                    self?.isRunning = false
                    self?.listener = nil
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    self?.start()
                default: break
                }
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener.start(queue: .global(qos: .userInitiated))
        self.listener = listener
        #endif
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        serverURL = nil
    }

    // MARK: - Publish our URL to iCloud so iOS can find us

    private func publishURLToiCloud() async {
        guard let url = serverURL,
              let root = iCloudSyncEngine.shared.eonCodeRoot
        else { return }

        let macInfoURL = root.appendingPathComponent("mac-server.json")
        let info: [String: String] = [
            "url": url.absoluteString,
            "deviceName": UIDevice.deviceName,
            "timestamp": Date().iso8601
        ]
        if let data = try? JSONSerialization.data(withJSONObject: info) {
            try? await iCloudSyncEngine.shared.writeData(data, to: macInfoURL)
        }
    }

    // MARK: - Resolve local IP address

    private func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp && !isLoopback,
               current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let candidate = String(cString: hostname)
                // Prefer en0 (Wi-Fi) addresses
                if let name = current.pointee.ifa_name.map({ String(cString: $0) }),
                   name.hasPrefix("en") {
                    address = candidate
                } else if address == nil {
                    address = candidate
                }
            }
            ptr = current.pointee.ifa_next
        }
        return address
    }

    // MARK: - Handle HTTP connection

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let data = data, !data.isEmpty else { return }
            let request = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor in
                let response = await self?.handleHTTPRequest(request) ?? HTTPResponse.notFound()
                self?.sendHTTPResponse(response, over: connection)
            }
        }
    }

    private func handleHTTPRequest(_ raw: String) async -> HTTPResponse {
        let lines = raw.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return .badRequest() }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return .badRequest() }

        let method = parts[0]
        let path = parts[1]

        var bodyData: Data? = nil
        if let bodyStart = raw.range(of: "\r\n\r\n") {
            let bodyString = String(raw[bodyStart.upperBound...])
            bodyData = bodyString.data(using: .utf8)
        }

        switch (method, path) {
        case ("GET", "/status"):
            return await handleStatusRequest()
        case ("GET", "/instructions"):
            return await handleGetInstructions()
        case ("POST", "/instructions"):
            return await handlePostInstruction(body: bodyData)
        case ("GET", let p) where p.hasPrefix("/files/"):
            let filePath = String(p.dropFirst(7))
            return await handleGetFile(path: filePath.removingPercentEncoding ?? filePath)
        case ("PUT", let p) where p.hasPrefix("/files/"):
            let filePath = String(p.dropFirst(7))
            return await handlePutFile(path: filePath.removingPercentEncoding ?? filePath, body: bodyData)
        case ("GET", "/ping"):
            let pong: [String: Any] = [
                "pong": true,
                "deviceName": UIDevice.deviceName,
                "serverURL": serverURL?.absoluteString ?? ""
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: pong) else { return .serverError() }
            return HTTPResponse(statusCode: 200, body: data, contentType: "application/json")
        default:
            return .notFound()
        }
    }

    private func handleStatusRequest() async -> HTTPResponse {
        let status: [String: Any] = [
            "device": UIDevice.deviceName,
            "isMac": UIDevice.isMac,
            "timestamp": Date().iso8601,
            "agentRunning": AgentEngine.shared.isRunning,
            "agentStatus": AgentEngine.shared.statusMessage,
            "serverURL": serverURL?.absoluteString ?? ""
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: status) else { return .serverError() }
        return HTTPResponse(statusCode: 200, body: data, contentType: "application/json")
    }

    private func handleGetInstructions() async -> HTTPResponse {
        let instructions = await InstructionQueue.shared.pendingInstructions()
        guard let data = try? JSONEncoder().encode(instructions) else { return .serverError() }
        return HTTPResponse(statusCode: 200, body: data, contentType: "application/json")
    }

    private func handlePostInstruction(body: Data?) async -> HTTPResponse {
        guard let body = body,
              let instruction = try? JSONDecoder().decode(Instruction.self, from: body)
        else { return .badRequest() }

        await InstructionQueue.shared.enqueue(instruction)
        return HTTPResponse(statusCode: 201, body: "{\"ok\":true}".data(using: .utf8)!, contentType: "application/json")
    }

    private func handleGetFile(path: String) async -> HTTPResponse {
        guard let root = iCloudSyncEngine.shared.eonCodeRoot else { return .notFound() }
        let url = root.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return .notFound() }
        return HTTPResponse(statusCode: 200, body: data, contentType: "application/octet-stream")
    }

    private func handlePutFile(path: String, body: Data?) async -> HTTPResponse {
        guard let body = body,
              let root = iCloudSyncEngine.shared.eonCodeRoot
        else { return .badRequest() }

        let url = root.appendingPathComponent(path)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try body.write(to: url)
            return HTTPResponse(statusCode: 200, body: "{\"ok\":true}".data(using: .utf8)!, contentType: "application/json")
        } catch {
            return .serverError()
        }
    }

    // MARK: - Send response

    private func sendHTTPResponse(_ response: HTTPResponse, over connection: NWConnection) {
        var headers = "HTTP/1.1 \(response.statusCode) \(response.statusText)\r\n"
        headers += "Content-Type: \(response.contentType)\r\n"
        headers += "Content-Length: \(response.body.count)\r\n"
        headers += "Connection: close\r\n"
        headers += "\r\n"

        let fullData = (headers.data(using: .utf8) ?? Data()) + response.body
        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - iOS Client

@MainActor
final class LocalNetworkClient {
    static let shared = LocalNetworkClient()

    private var macURL: URL?
    private var discoveryTask: Task<Void, Never>?

    func setMacAddress(_ url: URL) {
        macURL = url
        SettingsStore.shared.macServerURL = url.absoluteString
    }

    func postInstruction(_ instruction: Instruction) async throws {
        guard let base = resolvedBase() else { throw NetworkError.noServerURL }
        var request = URLRequest(url: base.appendingPathComponent("instructions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try instruction.encoded()
        request.timeoutInterval = 10
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 201 else {
            throw NetworkError.requestFailed
        }
    }

    func fetchStatus() async throws -> [String: Any] {
        guard let base = resolvedBase() else { throw NetworkError.noServerURL }
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("status"))
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Auto-discover Mac

    /// Tries all discovery methods in order: saved URL → iCloud file → subnet scan
    @discardableResult
    func discoverMac() async -> URL? {
        // 1. Try saved URL first (fastest)
        let saved = SettingsStore.shared.macServerURL
        if !saved.isEmpty, let url = URL(string: saved), await ping(url) {
            macURL = url
            return url
        }

        // 2. Try iCloud-published URL from Mac
        if let url = await readMacURLFromiCloud(), await ping(url) {
            macURL = url
            SettingsStore.shared.macServerURL = url.absoluteString
            return url
        }

        // 3. Scan subnet
        if let url = await subnetScan() {
            macURL = url
            SettingsStore.shared.macServerURL = url.absoluteString
            return url
        }

        return nil
    }

    /// Start background auto-discovery loop (iOS only)
    func startAutoDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = Task {
            while !Task.isCancelled {
                let currentURL = macURL
                let needsDiscovery: Bool
                if let url = currentURL {
                    needsDiscovery = !(await ping(url))
                } else {
                    needsDiscovery = true
                }
                if needsDiscovery {
                    await discoverMac()
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func stopAutoDiscovery() {
        discoveryTask?.cancel()
        discoveryTask = nil
    }

    // MARK: - Private helpers

    private func resolvedBase() -> URL? {
        if let url = macURL { return url }
        let saved = SettingsStore.shared.macServerURL
        if !saved.isEmpty, let url = URL(string: saved) {
            macURL = url
            return url
        }
        return nil
    }

    private func ping(_ url: URL) async -> Bool {
        var req = URLRequest(url: url.appendingPathComponent("ping"))
        req.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: req)) != nil
    }

    private func readMacURLFromiCloud() async -> URL? {
        guard let root = iCloudSyncEngine.shared.eonCodeRoot else { return nil }
        let macInfoURL = root.appendingPathComponent("mac-server.json")
        guard let data = try? await iCloudSyncEngine.shared.readData(from: macInfoURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let urlString = json["url"],
              let url = URL(string: urlString)
        else { return nil }

        // Only trust if written recently (< 5 minutes)
        if let ts = json["timestamp"], let date = ISO8601DateFormatter().date(from: ts),
           Date().timeIntervalSince(date) > 300 {
            return nil
        }
        return url
    }

    private func subnetScan() async -> URL? {
        let base = localSubnetBase() ?? "192.168.1"
        let port = Constants.Sync.localHTTPPort
        let hosts = (1...254).map { "\(base).\($0)" }

        for batch in hosts.chunkedInto(16) {
            let results = await withTaskGroup(of: URL?.self) { group in
                for host in batch {
                    group.addTask {
                        let url = URL(string: "http://\(host):\(port)")!
                        var req = URLRequest(url: url.appendingPathComponent("ping"))
                        req.timeoutInterval = 1
                        if let (data, _) = try? await URLSession.shared.data(for: req),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           json["pong"] as? Bool == true {
                            return url
                        }
                        return nil
                    }
                }
                var found: [URL] = []
                for await result in group {
                    if let url = result { found.append(url) }
                }
                return found
            }
            if let found = results.first { return found }
        }
        return nil
    }

    private func localSubnetBase() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0,
               current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_INET),
               let name = current.pointee.ifa_name.map({ String(cString: $0) }),
               name.hasPrefix("en") {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(current.pointee.ifa_addr,
                            socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                let parts = ip.split(separator: ".")
                if parts.count == 4 {
                    return "\(parts[0]).\(parts[1]).\(parts[2])"
                }
            }
            ptr = current.pointee.ifa_next
        }
        return nil
    }
}

// MARK: - Array chunking (local, avoids conflict with WorkerPool extension)

private extension Array {
    func chunkedInto(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

// MARK: - Helper types

struct HTTPResponse {
    let statusCode: Int
    let body: Data
    let contentType: String

    var statusText: String {
        switch statusCode {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Unknown"
        }
    }

    static func notFound() -> HTTPResponse {
        HTTPResponse(statusCode: 404, body: "{\"error\":\"not found\"}".data(using: .utf8)!, contentType: "application/json")
    }
    static func badRequest() -> HTTPResponse {
        HTTPResponse(statusCode: 400, body: "{\"error\":\"bad request\"}".data(using: .utf8)!, contentType: "application/json")
    }
    static func serverError() -> HTTPResponse {
        HTTPResponse(statusCode: 500, body: "{\"error\":\"server error\"}".data(using: .utf8)!, contentType: "application/json")
    }
}

enum NetworkError: LocalizedError {
    case noServerURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .noServerURL: return "Mac-serverns URL är inte konfigurerad"
        case .requestFailed: return "Nätverksanrop misslyckades"
        }
    }
}
