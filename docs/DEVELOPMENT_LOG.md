# Gyoza Island development log

Gyoza Island is a macOS notch panel with music controls, a file shelf, AirDrop drops and a front-camera mirror.

## Releases

| Version | Date | Release |
|---|---|---|
| 1.0 | 2026-05-06 | [v1.0](https://github.com/alfredswift31-botty/GyozaIsland/releases/tag/v1.0) |
| 1.1 | 2026-09-25 | [v1.1](https://github.com/alfredswift31-botty/GyozaIsland/releases/tag/v1.1) |

## 1.0 (May 2026)
1.0 built the notch-matched `NSPanel` (sized from `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`) and the hover expand/collapse. The panel sits below the drag-cursor window level so file drags land.

Pages:
- Music, via AppleScript.
- The file vault.
- The front-camera mirror.

It also added the AirDrop drop target and trackpad paging.

## 1.1 (September 2026): audit and reliability

This was a full audit of the 1.0 code, commit 242796a.

**Bugs fixed**
- **Constant re-rendering:** ContentView re-rendered on every system-wide mouse move and drag event. Its `@Published` values are now written only when they change.
- **Camera left on:** the mirror camera kept running, with its green light, after paging away. It now stops. Start/stop run on one queue, and the camera won't start if permission is granted after the mirror has closed.
- **Freezes when Music hangs:** Apple Events to Music had AppleScript's default 2-minute timeout, on the main thread. They now time out after 5 s, with a clear message.
- **Wasted artwork exports:** album artwork was exported on every sync (every 0.5 s near a track's end). It's now exported only when the track changes.
- **Locale bug:** playback times with comma decimals (`215,5`) now parse.
- **Stuck scrubber:** it now uses `@GestureState`, so a cancelled drag can't leave it on a stale position.
- **Double page turns:** a stale swipe unlock could release a newer swipe's lock early. It can't any more.
- **Drops:** file promises from Photos and Mail are materialised before going to the shelf or AirDrop, real file URLs are preferred over promises, and web links now go to AirDrop.

**Tightening**
- Cached the AirDrop and Music icons.
- Logging is debug-only, and dead swipe-threshold code is gone.
- VoiceOver labels on icon-only buttons.
- Friendlier messages when Automation is denied.
- `MediaManager.swift` is renamed to `MusicController.swift`.

**Housekeeping**
- Unit tests in `GyozaIslandTests`.
- A GitHub Actions build on macos-26 / Xcode 26 that runs the tests, then builds, ad-hoc signs and zips the app.
- Releases are published by running the Build workflow manually with a `release_tag`, commit 3f3b131. The development container can't push tags.
- The README was rewritten for 1.1, with install steps pointing at Releases.

## Verified
- CI is green: tests pass, and the Release build and packaging succeed.
- The v1.1 zip is attached to the release.

## Not verified
- The behaviour fixes were checked by code review and unit tests, not by running the app on a Mac from the development container.
- Worth a quick manual check: hover, swipes, drops from Photos and Mail, and the camera light going off.

## Ideas for next time
- Support other music players (Spotify) alongside Apple Music.
- Keep the file shelf across launches, as an option.

## Working notes
- The session's development branch was `claude/vigilant-dirac-3wnwtr`; releases come from `main`.
- To release: run Actions › Build › Run workflow on `main` with `release_tag: vX.Y`.
