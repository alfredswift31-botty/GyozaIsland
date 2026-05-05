import AppKit
import Combine
import Foundation

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var prefersPauseIcon = false
    @Published private(set) var trackTitle = "Apple Music"
    @Published private(set) var trackSubtitle = "Ready to play"
    @Published private(set) var artworkImage: NSImage?

    func togglePlayPause() {
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

        prefersPauseIcon.toggle()
        runCommand(
            """
            tell application id "com.apple.Music" to playpause
            """,
            label: "playpause"
        )
    }

    func nextTrack() {
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

        runCommand(
            """
            tell application id "com.apple.Music" to next track
            """,
            label: "next track"
        )
    }

    func previousTrack() {
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

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

            set artworkPath to POSIX path of (path to temporary items) & "gyoza-island-current-artwork"

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

                set artworkResult to ""
                try
                    if (count of artworks of current track) > 0 then
                        set rawArtwork to raw data of artwork 1 of current track
                        set outFile to open for access POSIX file artworkPath with write permission
                        set eof of outFile to 0
                        write rawArtwork to outFile
                        close access outFile
                        set artworkResult to artworkPath
                    end if
                on error
                    try
                        close access POSIX file artworkPath
                    end try
                    set artworkResult to ""
                end try

                return playbackState & linefeed & trackName & linefeed & artistName & linefeed & artworkResult
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
        let artworkPath = lines.dropFirst(3).first ?? ""

        prefersPauseIcon = playbackState == "playing"
        trackTitle = title.isEmpty ? "Apple Music" : title
        trackSubtitle = subtitle.isEmpty ? playbackState.capitalized : subtitle
        artworkImage = artworkPath.isEmpty ? nil : NSImage(contentsOfFile: artworkPath)
    }

    private func applyAppleScriptError(_ error: NSDictionary, label: String) {
        print("AppleScript error (\(label)):", error)

        let message = error[NSAppleScript.errorMessage] as? String
        let number = error[NSAppleScript.errorNumber] as? Int

        prefersPauseIcon = false
        trackTitle = "Apple Music"
        artworkImage = nil
        if let number, let message {
            trackSubtitle = "Music control failed (\(number)): \(message)"
        } else if let message {
            trackSubtitle = message
        } else {
            trackSubtitle = "Music control failed"
        }
    }

    func openMusicApp(activates: Bool = true) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Music") else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activates
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private var musicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    private func showMusicClosedMessage() {
        prefersPauseIcon = false
        trackTitle = "Apple Music"
        trackSubtitle = "Click artwork to open Music"
        artworkImage = nil
    }
}

private func executeAppleScript(_ source: String) -> (value: String?, error: NSDictionary?) {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    return (result?.stringValue, error)
}
