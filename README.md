# Gyoza Island

Gyoza Island is a macOS menu-bar panel app that replaces the notch with a living, gesture-driven island. It collapses to a pill that perfectly overlaps the physical notch at rest, and expands on hover to reveal music controls, a temporary file vault, and a front-camera mirror — all without ever leaving the top of your screen.

## Version 1.0

First public release. Core island panel, three-page layout, music controls with scrubber, temporary file vault with drag-and-drop and AirDrop, and front-camera mirror are all stable and shipped.

## Core Features

### Dynamic Island Panel
The island is an `NSPanel` anchored to the top of the screen at a window level above the menu bar but below the system drag cursor. It detects the exact physical notch dimensions at runtime using the macOS `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` APIs, so the resting pill matches the real notch silhouette precisely on any Mac. On non-notch Macs it sits flush against the menu bar top. The panel joins all Spaces and stays visible in fullscreen, always out of the way.

Hover over the notch to expand. Move away to collapse. The expansion and collapse are driven by spring-based SwiftUI animations interpolated against real pointer events from global and local `NSEvent` monitors — no polling.

### Music Controls
Page one shows the currently playing track from Apple Music: title, artist, album art, and a live playback scrubber. Playback position advances locally every 0.5 seconds and syncs back from the Music app every 5 seconds (or sooner near the end of a track). Album artwork is fetched via AppleScript and cached to a temporary file so the image loads without blocking the UI.

Controls:
- **Play / Pause** — toggles playback and flips the icon immediately for a responsive feel
- **Previous / Next track** — sent via AppleScript to Apple Music
- **Scrubber** — drag to seek; position is clamped and written back to the Music app in real time
- **Click album art** — opens the Music app if it is not already running

### Temporary File Vault
Page two is a drag-and-drop file shelf. Drag any file from Finder into the island and it is held in memory for the session. The island stays open while you go fetch more files, and collapses normally once you swipe back to another page. Drag items back out to wherever you need them. Dismiss individual files with the remove button.

The vault handles all three Finder drag flavours: modern promised-file-url drags, direct file URLs, and legacy `NSFilenamesPboardType` paths, so it works with every macOS version and every app that can drag a file.

### AirDrop Drop Target
Drop a file on the island while on any page other than the vault and it goes straight to AirDrop. The island triggers `NSSharingService` with the AirDrop sender directly. If AirDrop is unavailable it falls back to the system sharing picker. Drop on the vault page and the file is shelved instead.

### Mirror
Page three is a circular front-camera preview. Tap the camera icon to activate a live `AVCaptureSession` from the front-facing camera, horizontally mirrored so it feels like a real mirror. Tap again to stop the session and dismiss. Camera permission is requested on first activation.

### Trackpad Page Navigation
Swipe horizontally on the trackpad while the island is expanded to move between pages. The gesture uses both a local and a global `NSEvent` scroll monitor so it works even when another app is in front. Diagonal scrolling is filtered out — only swipes where the horizontal delta exceeds the vertical delta register. A 2.6x scroll multiplier and a 22-point threshold make page turns feel snappy without being accidental, and a 400 ms commit lock prevents double-fires.

## Tech Stack

- SwiftUI
- AppKit (`NSPanel`, `NSEvent` global and local monitors, `NSSharingService`, `NSFilePromiseReceiver`)
- AVFoundation (camera capture and preview)
- AppleScript (Apple Music playback control and now-playing info)
- QuartzCore (custom island shape animation)
- macOS 13+

## Project Status

Version 1.0 is the first stable release. All three pages are complete and the panel geometry, hover detection, drag handling, and gesture navigation are solid.

## Related

Built alongside [Gyoza Budget](https://github.com/alfredswift31-botty/GyozaBudget) — a SwiftUI personal finance app for iOS.
