import SwiftUI
import AVKit

// MARK: - MediaVideoPlayer

struct MediaVideoPlayer: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        #if os(macOS)
        macPlayer
        #else
        iOSPlayer
        #endif
    }

    #if os(macOS)
    var macPlayer: some View {
        VideoPlayer(player: player ?? AVPlayer())
            .onAppear { setupPlayer() }
            .onDisappear { player?.pause() }
    }
    #endif

    #if os(iOS)
    var iOSPlayer: some View {
        VideoPlayer(player: player ?? AVPlayer())
            .onAppear { setupPlayer() }
            .onDisappear { player?.pause() }
    }
    #endif

    private func setupPlayer() {
        let p = AVPlayer(url: url)
        p.play()
        player = p
    }
}

// MARK: - Preview

#Preview("MediaVideoPlayer") {
    MediaVideoPlayer(url: URL(string: "https://example.com/video.mp4")!)
        .frame(width: 400, height: 300)
}
