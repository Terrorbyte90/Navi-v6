import Foundation

// MARK: - Xcode Cloud Service
// Triggers Xcode Cloud builds via App Store Connect API.
// Works from any platform (iOS, macOS, server) — no local Xcode needed.

@MainActor
final class XcodeCloudService: ObservableObject {
    static let shared = XcodeCloudService()

    @Published var lastBuildStatus: String = ""
    @Published var isDeploying = false

    // App Store Connect API credentials (stored in Keychain)
    private var issuerID: String = ""
    private var keyID: String = ""
    private var privateKey: String = ""

    private let baseURL = "https://api.appstoreconnect.apple.com/v1"

    private init() {
        loadCredentials()
    }

    // MARK: - Credential Management

    private func loadCredentials() {
        issuerID = (try? KeychainManager.shared.get(key: "appstoreconnect_issuer_id")) ?? ""
        keyID = (try? KeychainManager.shared.get(key: "appstoreconnect_key_id")) ?? ""
        privateKey = (try? KeychainManager.shared.get(key: "appstoreconnect_private_key")) ?? ""
    }

    var isConfigured: Bool {
        !issuerID.isEmpty && !keyID.isEmpty && !privateKey.isEmpty
    }

    func configure(issuerID: String, keyID: String, privateKey: String) {
        self.issuerID = issuerID
        self.keyID = keyID
        self.privateKey = privateKey
        try? KeychainManager.shared.save(key: "appstoreconnect_issuer_id", value: issuerID)
        try? KeychainManager.shared.save(key: "appstoreconnect_key_id", value: keyID)
        try? KeychainManager.shared.save(key: "appstoreconnect_private_key", value: privateKey)
    }

    // MARK: - JWT Token Generation (ES256)

    private func generateJWT() throws -> String {
        let header = [
            "alg": "ES256",
            "kid": keyID,
            "typ": "JWT"
        ]

        let now = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = [
            "iss": issuerID,
            "iat": now,
            "exp": now + 1200, // 20 minutes
            "aud": "appstoreconnect-v1"
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerBase64 = headerData.base64URLEncoded
        let payloadBase64 = payloadData.base64URLEncoded
        let signingInput = "\(headerBase64).\(payloadBase64)"

        guard let signingData = signingInput.data(using: .utf8) else {
            throw XCError.jwtGeneration("Kunde inte skapa signing data")
        }

        // Sign with ES256 using Security framework
        let signature = try signES256(data: signingData)
        let signatureBase64 = signature.base64URLEncoded

        return "\(headerBase64).\(payloadBase64).\(signatureBase64)"
    }

    private func signES256(data: Data) throws -> Data {
        // Parse PEM private key
        let pemKey = privateKey
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        guard let keyData = Data(base64Encoded: pemKey) else {
            throw XCError.jwtGeneration("Ogiltig privat nyckel (base64)")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]

        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw XCError.jwtGeneration("Kunde inte skapa SecKey: \(error?.takeRetainedValue().localizedDescription ?? "okänt")")
        }

        guard let signature = SecKeyCreateSignature(
            secKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            throw XCError.jwtGeneration("Signering misslyckades: \(error?.takeRetainedValue().localizedDescription ?? "okänt")")
        }

        return signature
    }

    // MARK: - API Calls

    private func apiRequest(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        let token = try generateJWT()
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw XCError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw XCError.network("Inget HTTP-svar")
        }

        if http.statusCode >= 400 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Okänt fel"
            throw XCError.apiError(http.statusCode, errorBody)
        }

        return data
    }

    // MARK: - Xcode Cloud Operations

    /// List all Xcode Cloud workflows for the app
    func listWorkflows() async throws -> [XCWorkflow] {
        // First get the product (app) — list CI products
        let productsData = try await apiRequest("/ciProducts")
        let productsResponse = try JSONDecoder().decode(XCListResponse<XCProduct>.self, from: productsData)

        var allWorkflows: [XCWorkflow] = []

        for product in productsResponse.data {
            let workflowsData = try await apiRequest("/ciProducts/\(product.id)/workflows")
            let workflowsResponse = try JSONDecoder().decode(XCListResponse<XCWorkflow>.self, from: workflowsData)
            allWorkflows.append(contentsOf: workflowsResponse.data)
        }

        return allWorkflows
    }

    /// Trigger a build run for a specific workflow
    func startBuildRun(workflowID: String, gitReference: String? = nil) async throws -> XCBuildRun {
        var relationships: [String: Any] = [
            "workflow": [
                "data": [
                    "type": "ciWorkflows",
                    "id": workflowID
                ]
            ]
        ]

        var attributes: [String: Any] = [:]
        if let ref = gitReference {
            attributes["sourceBranchOrTag"] = [
                "kind": "BRANCH",
                "name": ref
            ]
        }

        let body: [String: Any] = [
            "data": [
                "type": "ciBuildRuns",
                "attributes": attributes.isEmpty ? [:] : attributes,
                "relationships": relationships
            ]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let data = try await apiRequest("/ciBuildRuns", method: "POST", body: bodyData)
        let response = try JSONDecoder().decode(XCSingleResponse<XCBuildRun>.self, from: data)
        return response.data
    }

    /// Get build run status
    func getBuildRunStatus(buildRunID: String) async throws -> XCBuildRun {
        let data = try await apiRequest("/ciBuildRuns/\(buildRunID)")
        let response = try JSONDecoder().decode(XCSingleResponse<XCBuildRun>.self, from: data)
        return response.data
    }

    // MARK: - High-level trigger (used by agents)

    func triggerBuild(scheme: String, branch: String? = nil) async -> String {
        guard isConfigured else {
            return """
            ❌ Xcode Cloud är inte konfigurerat.
            Saknar App Store Connect API-nycklar.

            Konfigurera med:
            1. Gå till https://appstoreconnect.apple.com → Användare och åtkomst → Integrationer → App Store Connect API
            2. Skapa en API-nyckel med Admin-behörighet
            3. Spara Issuer ID, Key ID, och ladda ned .p8-filen
            4. I Navi: Inställningar → Xcode Cloud → Ange API-nycklar

            Eller använd verktyget get_api_key för att hämta nycklar från keychain:
            - appstoreconnect_issuer_id
            - appstoreconnect_key_id
            - appstoreconnect_private_key
            """
        }

        isDeploying = true
        lastBuildStatus = "Söker workflows..."
        defer { isDeploying = false }

        do {
            // Find matching workflow
            let workflows = try await listWorkflows()

            guard !workflows.isEmpty else {
                return "❌ Inga Xcode Cloud-workflows hittades. Konfigurera Xcode Cloud i Xcode eller App Store Connect."
            }

            // Match by scheme name or use first workflow
            let workflow = workflows.first { w in
                w.attributes.name.lowercased().contains(scheme.lowercased())
            } ?? workflows[0]

            lastBuildStatus = "Startar build: \(workflow.attributes.name)..."

            // Trigger build
            let buildRun = try await startBuildRun(
                workflowID: workflow.id,
                gitReference: branch
            )

            lastBuildStatus = "Build startad!"

            // Poll for status (max 5 minutes for initial status)
            var currentRun = buildRun
            let startTime = Date()
            let maxWait: TimeInterval = 300 // 5 min

            while Date().timeIntervalSince(startTime) < maxWait {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15s
                currentRun = try await getBuildRunStatus(buildRunID: buildRun.id)

                let status = currentRun.attributes.executionProgress ?? "PENDING"
                lastBuildStatus = "Build: \(status)"

                if status == "COMPLETE" || status == "FAILED" {
                    break
                }
            }

            let finalStatus = currentRun.attributes.completionStatus ?? currentRun.attributes.executionProgress ?? "UNKNOWN"

            if finalStatus == "SUCCEEDED" || finalStatus == "COMPLETE" {
                return """
                ✅ Xcode Cloud build klar!
                Workflow: \(workflow.attributes.name)
                Build Run ID: \(currentRun.id)
                Status: \(finalStatus)

                Appen bearbetas nu av Apple och kommer att dyka upp i TestFlight inom kort.
                """
            } else if finalStatus == "FAILED" || finalStatus == "ERRORED" {
                return """
                ❌ Xcode Cloud build misslyckades.
                Workflow: \(workflow.attributes.name)
                Build Run ID: \(currentRun.id)
                Status: \(finalStatus)

                Kontrollera loggar i App Store Connect → Xcode Cloud.
                """
            } else {
                return """
                🟡 Xcode Cloud build pågår.
                Workflow: \(workflow.attributes.name)
                Build Run ID: \(currentRun.id)
                Status: \(finalStatus)

                Bygget körs i bakgrunden. Kontrollera status i App Store Connect.
                En push-notis skickas via ntfy.sh när bygget är klart.
                """
            }
        } catch let error as XCError {
            return "❌ Xcode Cloud-fel: \(error.localizedDescription)"
        } catch {
            return "❌ Xcode Cloud-fel: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Models

struct XCListResponse<T: Decodable>: Decodable {
    let data: [T]
}

struct XCSingleResponse<T: Decodable>: Decodable {
    let data: T
}

struct XCProduct: Decodable {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let productType: String?
    }
}

struct XCWorkflow: Decodable, Identifiable {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let name: String
        let description: String?
        let isEnabled: Bool?
        let lastModifiedDate: String?
    }
}

struct XCBuildRun: Decodable, Identifiable {
    let id: String
    let type: String
    let attributes: Attributes

    struct Attributes: Decodable {
        let executionProgress: String?
        let completionStatus: String?
        let startedDate: String?
        let finishedDate: String?
        let number: Int?
    }
}

// MARK: - Errors

enum XCError: LocalizedError {
    case jwtGeneration(String)
    case invalidURL(String)
    case network(String)
    case apiError(Int, String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .jwtGeneration(let msg): return "JWT-fel: \(msg)"
        case .invalidURL(let path): return "Ogiltig URL: \(path)"
        case .network(let msg): return "Nätverksfel: \(msg)"
        case .apiError(let code, let body): return "API-fel (\(code)): \(String(body.prefix(500)))"
        case .notConfigured: return "Xcode Cloud är inte konfigurerat"
        }
    }
}

// MARK: - Data Extension for Base64URL

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
