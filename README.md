# Gyoza Island

Gyoza Island is a macOS Dynamic Island-style panel app that lives at the top of your screen, bringing music controls, a temporary file vault, and a front-camera mirror into a sleek, gesture-driven interface that snaps neatly over the notch.

## Latest Commit

**Add mirror page with front camera preview** — added a circular live camera preview to the mirror page, with sizing and positioning tuned to sit cleanly within the island panel without overlapping the notch.

## Core Features

### Music Controls
Now-playing information with smooth animated transitions, album art, and a media playback scrubber for quick seeking — all within the island panel.

### Temporary File Vault
Drop files into the island to hold them temporarily. Drag out when needed. Files are stored in-memory for the session and cleared on close.

### Mirror
A circular front-camera preview that activates on tap, letting you use the island as a quick mirror. Tap again to dismiss.

### Dynamic Island Panel
The panel collapses to a pill that matches the real macOS notch at rest, and expands on hover with smooth spring-based animations. Swipe or scroll between pages.

## Tech Stack

- SwiftUI
- AVFoundation (camera capture)
- AppKit panel (LSUIElement, always-on-top)
- NSEvent global and local monitors
- Custom island shape animation
- macOS

## Project Status

Active development. Core pages (music, vault, mirror) are stable. Layout and interaction polish ongoing.

## Related

Built alongside [Gyoza Budget](https://github.com/alfredswift31-botty/GyozaBudget) — a SwiftUI personal finance app for iOS.
