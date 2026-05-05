import AppKit
import Combine
import Foundation

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var prefersPauseIcon = false
    @Published private(set) var trackTitle = "Apple Music"
    @Published private(set) var trackSubtitle = "Ready to play"

    func togglePlayPause() {
        prefersPauseIcon.toggle()
        openMusicIfNeeded()
        runCommand(
            """
            tell application id "com.apple.Music" to playpause
            """,
            label: "playpause"
        )
    }

    func nextTrack() {
        openMusicIfNeeded()
        runCommand(
            """
            tell application id "com.apple.Music" to next track
            """,
            label: "next track"
        )
    }

    func previousTrack() {
        openMusicIfNeeded()
        runCommand(
            """
            tell application id "com.apple.Music" to previous track
            """,
            label: "previous track"
        )
    }

    func refreshNowPlaying() {
        runInfoScript(
            """
            if application id "com.apple.Music" is not running then
                return "stopped" & linefeed & "Apple Music" & linefeed & "Not playing"
            end if

            tell application id "com.apple.Music"
                set playbackState to player state as string

                if playbackState is "stopped" then
                    return playbackState & linefeed & "Apple Music" & linefeed & "Not playing"
                end if

                set trackName to ""
                set artistName to ""

                try
                    set trackName to name of current track
                end try

                try
                    set artistName to artist of current track
                end try

                if artistName is "" then
                    try
                        set artistName to album of current track
                    end try
                end if

                if trackName is "" then set trackName to "Apple Music"
                if artistName is "" then set artistName to playbackState

                return playbackState & linefeed & trackName & linefeed & artistName
            end tell
            """,
            label: "now playing"
        )
    }

    private func runCommand(_ source: String, label: String) {
        print("Running AppleScript (\(label)):", source)

        let result = executeAppleScript(source)

        if let error = result.error {
            applyAppleScriptError(error, label: label)
        } else {
            print("AppleScript result:", result.value ?? "Success, no return value")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    private func runInfoScript(_ source: String, label: String) {
        let result = executeAppleScript(source)

        if let error = result.error {
            applyAppleScriptError(error, label: label)
            return
        }

        applyNowPlaying(result.value)
    }

    private func applyNowPlaying(_ value: String?) {
        let lines = (value ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let playbackState = lines.first ?? "stopped"
        let title = lines.dropFirst().first ?? "Apple Music"
        let subtitle = lines.dropFirst(2).first ?? "Not playing"

        prefersPauseIcon = playbackState == "playing"
        trackTitle = title.isEmpty ? "Apple Music" : title
        trackSubtitle = subtitle.isEmpty ? playbackState.capitalized : subtitle
    }

    private func applyAppleScriptError(_ error: NSDictionary, label: String) {
        print("AppleScript error (\(label)):", error)

        let message = error[NSAppleScript.errorMessage] as? String
        let number = error[NSAppleScript.errorNumber] as? Int

        prefersPauseIcon = false
        trackTitle = "Apple Music"
        if let number, let message {
            trackSubtitle = "Music control failed (\(number)): \(message)"
        } else if let message {
            trackSubtitle = message
        } else {
            trackSubtitle = "Music control failed"
        }
    }

    private func openMusicIfNeeded() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty else {
            return
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

private func executeAppleScript(_ source: String) -> (value: String?, error: NSDictionary?) {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    return (result?.stringValue, error)
}
