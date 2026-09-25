//
//  GyozaIslandTests.swift
//  GyozaIslandTests
//
//  Created by Aung Hpone Moe on 13/04/2026.
//

import Foundation
import Testing
@testable import GyozaIsland

@MainActor
struct NowPlayingSnapshotTests {

    @Test func parsesPlayingTrack() {
        let snapshot = NowPlayingSnapshot(scriptOutput: "playing\nSong\nArtist\nABC123\n42.5\n215.25")

        #expect(snapshot.isPlaying)
        #expect(snapshot.hasTrack)
        #expect(snapshot.title == "Song")
        #expect(snapshot.subtitle == "Artist")
        #expect(snapshot.trackID == "ABC123")
        #expect(snapshot.position == 42.5)
        #expect(snapshot.duration == 215.25)
    }

    @Test func acceptsCommaDecimalSeparator() {
        // AppleScript formats reals with the user's locale, e.g. German.
        let snapshot = NowPlayingSnapshot(scriptOutput: "paused\nSong\nArtist\nABC123\n42,5\n215,25")

        #expect(!snapshot.isPlaying)
        #expect(snapshot.position == 42.5)
        #expect(snapshot.duration == 215.25)
    }

    @Test func acceptsExponentNotation() {
        // AppleScript prints reals of 10000 and up as "1.2345E+4".
        let snapshot = NowPlayingSnapshot(scriptOutput: "playing\nMix\nDJ\nABC123\n1.2E+4\n1.2345E+4")

        #expect(snapshot.position == 12000)
        #expect(snapshot.duration == 12345)
    }

    @Test func clampsPositionToDuration() {
        let snapshot = NowPlayingSnapshot(scriptOutput: "playing\nSong\nArtist\nABC123\n300\n200")

        #expect(snapshot.position == 200)
    }

    @Test func emptyOutputMeansStopped() {
        let snapshot = NowPlayingSnapshot(scriptOutput: nil)

        #expect(!snapshot.hasTrack)
        #expect(snapshot.title == "Apple Music")
        #expect(snapshot.subtitle == "Not playing")
        #expect(snapshot.position == 0)
        #expect(snapshot.duration == 0)
    }

    @Test func emptySubtitleFallsBackToState() {
        let snapshot = NowPlayingSnapshot(scriptOutput: "paused\n\n\n\n0\n0")

        #expect(snapshot.title == "Apple Music")
        #expect(snapshot.subtitle == "Paused")
    }

    @Test func artworkKeyChangesWithTrack() {
        let first = NowPlayingSnapshot(scriptOutput: "playing\nSong\nArtist\nAAA\n1\n100")
        let later = NowPlayingSnapshot(scriptOutput: "playing\nSong\nArtist\nAAA\n50\n100")
        let next = NowPlayingSnapshot(scriptOutput: "playing\nOther\nArtist\nBBB\n1\n100")

        #expect(first.artworkKey == later.artworkKey)
        #expect(first.artworkKey != next.artworkKey)
    }
}

@MainActor
struct TemporaryShelfTests {

    @Test func addingTheSameFileTwiceKeepsOneItem() {
        let state = IslandPanelState()
        let url = URL(fileURLWithPath: "/tmp/gyoza-example.txt")

        state.addTemporaryShelfFiles([url, url])
        state.addTemporaryShelfFiles([URL(fileURLWithPath: "/tmp/./gyoza-example.txt")])

        #expect(state.temporaryShelfItems.count == 1)
    }

    @Test func ignoresNonFileURLs() {
        let state = IslandPanelState()

        state.addTemporaryShelfFiles([URL(string: "https://example.com")!])

        #expect(state.temporaryShelfItems.isEmpty)
    }

    @Test func removesOnlyTheChosenItem() {
        let state = IslandPanelState()
        state.addTemporaryShelfFiles([
            URL(fileURLWithPath: "/tmp/gyoza-a.txt"),
            URL(fileURLWithPath: "/tmp/gyoza-b.txt")
        ])

        state.removeTemporaryShelfItem(state.temporaryShelfItems[0])

        #expect(state.temporaryShelfItems.map(\.url.lastPathComponent) == ["gyoza-b.txt"])
    }
}
