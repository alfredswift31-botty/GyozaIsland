import Combine
import Foundation

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var prefersPauseIcon = false

    func togglePlayPause() {
        prefersPauseIcon.toggle()
        runAppleScript(
            """
            if application id "com.apple.Music" is not running then
                tell application id "com.apple.Music" to launch
                delay 0.5
            end if

            tell application id "com.apple.Music" to playpause
            """,
            label: "playpause"
        )
    }

    func nextTrack() {
        runAppleScript(
            """
            if application id "com.apple.Music" is not running then
                tell application id "com.apple.Music" to launch
                delay 0.5
            end if

            tell application id "com.apple.Music" to next track
            """,
            label: "next track"
        )
    }

    func previousTrack() {
        runAppleScript(
            """
            if application id "com.apple.Music" is not running then
                tell application id "com.apple.Music" to launch
                delay 0.5
            end if

            tell application id "com.apple.Music" to previous track
            """,
            label: "previous track"
        )
    }

    private func runAppleScript(_ source: String, label: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            print("Running AppleScript (\(label)):", source)

            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)

            if let error {
                print("AppleScript error:", error)
            } else {
                print("AppleScript result:", result?.stringValue ?? "Success, no return value")
            }
        }
    }
}
