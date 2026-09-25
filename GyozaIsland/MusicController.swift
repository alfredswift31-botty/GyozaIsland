import AppKit
import Combine
import Foundation

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var prefersPauseIcon = false
    @Published private(set) var trackTitle = "Apple Music"
    @Published private(set) var trackSubtitle = "Ready to play"
    @Published private(set) var artworkImage: NSImage?
    @Published private(set) var playbackPosition: Double = 0
    @Published private(set) var playbackDuration: Double = 0
    @Published private(set) var nowPlayingID = "stopped"

    private var progressTimer: AnyCancellable?
    private var progressRefreshTick = 0
    private var isRefreshingNowPlaying = false
    // Track the artwork on screen belongs to, so it is only re-exported when
    // the track changes instead of on every sync.
    private var artworkKey: String?

    init() {
        progressTimer = Timer
            .publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tickPlaybackProgress()
            }
    }

    func togglePlayPause() {
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

        prefersPauseIcon.toggle()
        runCommand("playpause", label: "playpause")
    }

    func nextTrack() {
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

        runCommand("next track", label: "next track")
    }

    func previousTrack() {
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

        runCommand("previous track", label: "previous track")
    }

    func seek(to position: Double) {
        guard playbackDuration > 0 else { return }
        guard musicIsRunning else {
            showMusicClosedMessage()
            return
        }

        let safePosition = min(max(position, 0), playbackDuration)
        playbackPosition = safePosition
        runCommand("set player position to \(String(format: "%.3f", safePosition))", label: "seek")
    }

    func refreshNowPlaying() {
        guard !isRefreshingNowPlaying else { return }
        isRefreshingNowPlaying = true
        defer { isRefreshingNowPlaying = false }

        let result = executeAppleScript(Self.nowPlayingScript)

        if let error = result.error {
            applyAppleScriptError(error, label: "now playing")
            return
        }

        applyNowPlaying(NowPlayingSnapshot(scriptOutput: result.value))
    }

    private func runCommand(_ command: String, label: String) {
        debugLog("Running AppleScript (\(label))")

        let result = executeAppleScript(
            """
            with timeout of \(Self.appleEventTimeout) seconds
                tell application id "com.apple.Music" to \(command)
            end timeout
            """
        )

        if let error = result.error {
            applyAppleScriptError(error, label: label)
        } else {
            debugLog("AppleScript result: \(result.value ?? "Success, no return value")")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.refreshNowPlaying()
        }
    }

    private func applyNowPlaying(_ snapshot: NowPlayingSnapshot) {
        prefersPauseIcon = snapshot.isPlaying
        trackTitle = snapshot.title
        trackSubtitle = snapshot.subtitle
        playbackPosition = snapshot.position
        playbackDuration = snapshot.duration
        nowPlayingID = [snapshot.title, snapshot.subtitle, String(format: "%.3f", snapshot.duration)]
            .joined(separator: "|")
        refreshArtworkIfNeeded(for: snapshot)
    }

    /// Exporting artwork means pulling the raw image through an Apple Event,
    /// writing it to disk and decoding it, all on the main thread. Only do that
    /// when the track changes, or when the last attempt found nothing (streamed
    /// tracks can take a moment to expose their artwork).
    private func refreshArtworkIfNeeded(for snapshot: NowPlayingSnapshot) {
        guard snapshot.hasTrack else {
            clearArtwork()
            return
        }
        guard snapshot.artworkKey != artworkKey || artworkImage == nil else { return }

        artworkKey = snapshot.artworkKey
        let result = executeAppleScript(Self.artworkScript)
        if let error = result.error {
            debugLog("AppleScript error (artwork): \(error)")
        }

        let artworkPath = result.value ?? ""
        artworkImage = artworkPath.isEmpty ? nil : NSImage(contentsOfFile: artworkPath)
    }

    private func clearArtwork() {
        artworkImage = nil
        artworkKey = nil
    }

    private func applyAppleScriptError(_ error: NSDictionary, label: String) {
        debugLog("AppleScript error (\(label)): \(error)")

        let message = error[NSAppleScript.errorMessage] as? String
        let number = error[NSAppleScript.errorNumber] as? Int

        prefersPauseIcon = false
        trackTitle = "Apple Music"
        clearArtwork()
        playbackPosition = 0
        playbackDuration = 0
        nowPlayingID = "error"
        if number == -1743 {
            // errAEEventNotPermitted: Automation access to Music was denied.
            trackSubtitle = "Allow in Settings › Automation"
        } else if number == -1712 {
            // errAETimeout: Music is hung or blocked on a dialog.
            trackSubtitle = "Music isn't responding"
        } else if let number, let message {
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

    private func tickPlaybackProgress() {
        guard prefersPauseIcon else {
            progressRefreshTick = 0
            return
        }

        if playbackDuration > 0 {
            playbackPosition = min(playbackPosition + 0.5, playbackDuration)
        }

        progressRefreshTick += 1
        let isNearTrackEnd = playbackDuration > 0 && playbackDuration - playbackPosition <= 5
        if progressRefreshTick >= 10 || isNearTrackEnd {
            progressRefreshTick = 0
            refreshNowPlaying()
        }
    }

    private func showMusicClosedMessage() {
        prefersPauseIcon = false
        trackTitle = "Apple Music"
        trackSubtitle = "Click artwork to open Music"
        clearArtwork()
        playbackPosition = 0
        playbackDuration = 0
        nowPlayingID = "closed"
    }

    // NSAppleScript runs synchronously on the main thread. Without a timeout, a
    // hung Music (or one blocked on a modal dialog) would freeze the island for
    // AppleScript's default of two minutes.
    private static let appleEventTimeout = 5

    private static let nowPlayingScript = """
        if application id "com.apple.Music" is not running then
            return "stopped" & linefeed & "Apple Music" & linefeed & "Not playing" & linefeed & "" & linefeed & "0" & linefeed & "0"
        end if

        tell application id "com.apple.Music"
            with timeout of \(appleEventTimeout) seconds
                set playbackState to player state as string

                if playbackState is "stopped" then
                    return playbackState & linefeed & "Apple Music" & linefeed & "Not playing" & linefeed & "" & linefeed & "0" & linefeed & "0"
                end if

                set trackName to ""
                set artistName to ""
                set trackID to ""
                set trackPosition to 0
                set trackDuration to 0

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

                try
                    set trackID to persistent ID of current track
                end try

                try
                    set trackPosition to player position
                end try

                try
                    set trackDuration to duration of current track
                end try

                return playbackState & linefeed & trackName & linefeed & artistName & linefeed & trackID & linefeed & trackPosition & linefeed & trackDuration
            end timeout
        end tell
        """

    private static let artworkScript = """
        if application id "com.apple.Music" is not running then return ""

        set artworkPath to POSIX path of (path to temporary items) & "gyoza-island-current-artwork"

        tell application id "com.apple.Music"
            with timeout of \(appleEventTimeout) seconds
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
                return artworkResult
            end timeout
        end tell
        """
}

/// One reading of Music's state, parsed from the now-playing script's
/// linefeed-separated output: state, title, artist, persistent ID, position,
/// duration.
struct NowPlayingSnapshot {
    let state: String
    let title: String
    let subtitle: String
    let trackID: String
    let position: Double
    let duration: Double

    var isPlaying: Bool { state == "playing" }
    var hasTrack: Bool { state != "stopped" }

    /// Radio streams can keep one persistent ID across songs, so the visible
    /// text is part of the key too.
    var artworkKey: String { [trackID, title, subtitle].joined(separator: "|") }

    init(scriptOutput: String?) {
        let lines = (scriptOutput ?? "")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        func line(_ index: Int) -> String? {
            lines.indices.contains(index) ? lines[index] : nil
        }

        let rawState = line(0) ?? ""
        let state = rawState.isEmpty ? "stopped" : rawState
        let rawTitle = line(1) ?? ""
        let duration = Self.seconds(from: line(5))

        self.state = state
        self.title = rawTitle.isEmpty ? "Apple Music" : rawTitle
        if let rawSubtitle = line(2) {
            self.subtitle = rawSubtitle.isEmpty ? state.capitalized : rawSubtitle
        } else {
            self.subtitle = "Not playing"
        }
        self.trackID = line(3) ?? ""
        self.position = min(Self.seconds(from: line(4)), duration)
        self.duration = duration
    }

    /// AppleScript formats reals with the user's decimal separator ("215,5" in
    /// many locales) and uses exponent notation from 10000 up ("1.2345E+4").
    private static func seconds(from text: String?) -> Double {
        guard let text,
              let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else {
            return 0
        }
        return max(value, 0)
    }
}

private func executeAppleScript(_ source: String) -> (value: String?, error: NSDictionary?) {
    var error: NSDictionary?
    let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
    return (result?.stringValue, error)
}
