import AVKit
import SwiftUI

/// AVPlayerViewController supplies Apple's native full-screen, AirPlay,
/// Picture in Picture and embedded HLS subtitle controls without replacing the
/// surrounding SwiftUI navigation hierarchy.
struct NativeCoursePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = false
        }
        controller.updatesNowPlayingInfoCenter = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}
