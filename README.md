# Gyoza Island

Gyoza Island is a macOS panel app that sits at the notch. At rest it collapses to a pill that matches the physical notch cutout. Hover over it and it expands into a card with music controls, a file shelf, and a front-camera mirror. Move away and it folds back up.

## Version 1.1

A reliability and polish pass over 1.0. Nothing looks different, but a lot behaves better:

- **Smoother while you use the Mac.** The island no longer re-renders on every mouse move anywhere on screen, or on every drag event.
- **No more freezes when Music hangs.** Every Apple Event to Music now times out after five seconds instead of AppleScript's default two minutes.
- **Less work per sync.** Album artwork is exported only when the track changes, not every five seconds (and every half second near the end of a track).
- **Camera turns off when you leave the mirror.** Swiping to another page used to leave the camera, and its green light, running off-screen.
- **More drop sources.** Files from Photos, Mail and other apps that hand over file promises now land on the shelf and in AirDrop. Web links dropped on the island go to AirDrop.
- **Scrubber can't get stuck.** A drag cut short by a track change no longer freezes the scrubber.
- **Page swipes are single swipes.** Two quick swipes can no longer release each other's lock and double-turn a page.
- **Locale-proof playback times.** Positions like `215,5` (comma decimals) are parsed correctly.
- **Clearer errors.** A denied Automation permission now says where to fix it.
- VoiceOver labels on the icon-only buttons, debug logging kept out of Release builds, unit tests, and a CI build.

## What it does

### Island panel

The panel is an `NSPanel` that lives above the menu bar but below the system drag cursor, so file drags still land correctly. It reads the actual notch dimensions at runtime using `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, which means the resting pill matches the physical cutout exactly rather than being an approximation. On Macs without a notch it sits at the top of the menu bar instead. It joins all Spaces and stays visible in fullscreen.

Hover detection uses global and local `NSEvent` monitors on mouse-moved and drag events. No polling. The expand and collapse animations are SwiftUI spring transitions driven by the pointer position.

### Music controls

Page one shows the track playing in Apple Music: title, artist, artwork, and a scrubber. Playback position ticks forward locally every 0.5 seconds. Every five seconds (and every half second within the last five seconds of a track) it syncs back from the Music app via AppleScript. Artwork is written to a temp file only when the track changes.

Controls: play/pause, previous, next, and the scrubber. The play/pause icon flips immediately on tap rather than waiting for the AppleScript round-trip. Clicking the artwork opens the Music app.

AppleScript runs synchronously on the main thread, so each call is capped at five seconds. If Music is hung or showing a dialog, the island says so instead of freezing.

### File vault

Page two is a drag-and-drop shelf. Drop files in and they stay for the session. The island stays open while you go fetch more files, and collapses normally after you swipe away. Remove individual items with the button on each row, or drag them back out.

Drops are resolved in order: direct file URLs (Finder and most apps), legacy `NSFilenamesPboardType` paths, then file promises via `NSFilePromiseReceiver`. Promised files (Photos, Mail attachments) are written to a session-only temp folder that is cleared on the next launch.

### AirDrop drop target

Drop a file or a web link on the island while on any page other than the vault and it goes straight to `NSSharingService` with the AirDrop sender. Falls back to the system sharing picker if AirDrop can't take the items.

### Mirror

Page three has a circular front-camera preview. Tap the icon to start an `AVCaptureSession` from the front camera, flipped horizontally so it reads like a mirror. Tap again, swipe to another page, or move away to stop it. Camera permission gets requested on first tap.

### Trackpad navigation

Horizontal trackpad swipes page between sections. Both local and global scroll monitors handle events, so swiping works even when another app is in front. Vertical and diagonal scroll events are filtered out. The gesture uses a 2.6x multiplier against a 22-point threshold, and a 400 ms lock after each commit prevents double-fires.

## Install

Every push is built by GitHub Actions on a Mac runner. To get the latest build:

1. Download `GyozaIsland.zip` from the latest [release](https://github.com/alfredswift31-botty/GyozaIsland/releases), or from the newest green run of the [Build workflow](https://github.com/alfredswift31-botty/GyozaIsland/actions/workflows/build.yml).
2. Unzip until you have `GyozaIsland.app`, quit the running copy, and drag the new one into Applications, replacing the old one.
3. The CI build is ad-hoc signed, not notarized. The first time, right-click the app and choose **Open** (or allow it under System Settings › Privacy & Security).
4. Because the signature differs from a build made in your own Xcode, macOS asks again for Music (Automation) and Camera access.

## Building

Open `GyozaIsland.xcodeproj` in Xcode 26 and run the `GyozaIsland` scheme. Unit tests live in `GyozaIslandTests` (Swift Testing).

## Tech

- SwiftUI
- AppKit (`NSPanel`, `NSEvent` monitors, `NSSharingService`, `NSFilePromiseReceiver`)
- AVFoundation
- AppleScript (Music playback)
- macOS 15.6+

## Related

[Gyoza Budget](https://github.com/alfredswift31-botty/GyozaBudget) is a SwiftUI budgeting app for iOS, built alongside this one.
