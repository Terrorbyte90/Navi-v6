import Foundation
import WebKit
#if os(iOS)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

// MARK: - ScreenshotAnalyzer
// Fallback: captures WKWebView screenshot and sends to Claude vision.

struct ScreenshotAnalyzer {

    @MainActor
    static func takeScreenshot(from webView: WKWebView) async throws -> Data {
        return try await withCheckedThrowingContinuation { cont in
            let config = WKSnapshotConfiguration()
            webView.takeSnapshot(with: config) { image, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard let image = image else {
                    cont.resume(throwing: BrowserError.screenshotFailed)
                    return
                }

                #if os(iOS)
                guard let data = image.jpegData(compressionQuality: 0.7) else {
                    cont.resume(throwing: BrowserError.screenshotFailed)
                    return
                }
                cont.resume(returning: data)
                #else
                guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                    cont.resume(throwing: BrowserError.screenshotFailed)
                    return
                }
                cont.resume(returning: data)
                #endif
            }
        }
    }

    static func analyze(
        screenshotData: Data,
        goal: String,
        context: String,
        apiClient: ClaudeAPIClient
    ) async throws -> String {
        let messages = [ChatMessage(
            role: .user,
            content: [
                .image(screenshotData, mimeType: "image/jpeg"),
                .text("""
                Mål: \(goal)

                Kontext: \(context)

                Titta på skärmbilden och svara:
                1. Vad ser du på sidan?
                2. Vad ska nästa steg vara för att uppnå målet?
                3. Om du kan, ange exakt vilket element du ska interagera med (text på knapp, länktext, etc.)

                Svara koncist på svenska.
                """)
            ]
        )]

        let (response, _) = try await apiClient.sendMessage(
            messages: messages,
            model: .sonnet45, // Vision needs Sonnet+
            systemPrompt: "Du är en webbläsaragent som analyserar skärmbilder.",
            maxTokens: 512
        )
        return response
    }
}
