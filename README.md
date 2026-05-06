# Gyoza Island

Gyoza Island is a macOS panel app that sits at the notch. At rest it collapses to a pill that matches the physical notch cutout. Hover over it and it expands into a card with music controls, a file shelf, and a front-camera mirror. Move away and it folds back up.

## Version 1.0

First release. The panel, three pages, music controls with scrubber, file vault with drag-and-drop and AirDrop, and the mirror are all working and stable.

## What it does

### Island panel

The panel is an `NSPanel` that lives above the menu bar but below the system drag cursor, so file drags still land correctly. It reads the actual notch dimensions at runtime using `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, which means the resting pill matches the physical cutout exactly rather than being an approximation. On Macs without a notch it sits at the top of the menu bar instead. It joins all Spaces and stays visible in fullscreen.

Hover detection uses global and local `NSEvent` monitors on mouse-moved and drag events. No polling. The expand and collapse animations are SwiftUI spring transitions driven by the pointer position.

### Music controls

Page one shows the track playing in Apple Music: title, artist, artwork, and a scrubber. Playback position ticks forward locally every 0.5 seconds. Every five seconds (or within the last five seconds of a track) it syncs back from the Music app via AppleScript. Artwork gets written to a temp file so the image loads without blocking anything.

Controls: play/pause, previous, next, and the scrubber. The play/pause icon flips immediately on tap rather than waiting for the AppleScript round-trip. Clicking the artwork opens the Music app if it is closed.

### File vault

Page two is a drag-and-drop shelf. Drop files in and they stay for the session. The island stays open while you go fetch more files, and collapses normally after you swipe away. Remove individual items with the button on each row.

It handles modern Finder drags using `NSFilePromiseReceiver`, direct file URLs, and legacy `NSFilenamesPboardType` paths. Finder on recent macOS leads with promised URLs before the file data exists, so the vault handles that path too.

### AirDrop drop target

Drop a file on the island while on any page other than the vault and it goes straight to `NSSharingService` with the AirDrop sender. Falls back to the system sharing picker if AirDrop is not available.

### Mirror

Page three has a circular front-camera preview. Tap the icon to start an `AVCaptureSession` from the front camera, flipped horizontally so it reads like a mirror. Tap again to stop. Camera permission gets requested on first tap.

### Trackpad navigation

Horizontal trackpad swipes page between sections. Both local and global scroll monitors handle events, so swiping works even when another app is in front. Vertical and diagonal scroll events are filtered out. The gesture uses a 2.6x multiplier against a 22-point threshold, and a 400 ms lock after each commit prevents double-fires.

## Tech

- SwiftUI
- AppKit (`NSPanel`, `NSEvent` monitors, `NSSharingService`, `NSFilePromiseReceiver`)
- AVFoundation
- AppleScript (Music playback)
- macOS 13+

## Related

[Gyoza Budget](https://github.com/alfredswift31-botty/GyozaBudget) is a SwiftUI budgeting app for iOS, built alongside this one.
