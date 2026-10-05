# Tiny Vinyl

A tiny, translucent Spotify player for your Mac, with **Mochi**: a little cat in headphones who keeps you company while you listen.

Built with **SwiftUI + AppKit**. Runs locally without a web server, Spotify API key, or separate account login.

## Features

- Compact, draggable **300 × 510** frosted-glass window.
- An original animated cat with a hoodie, swishing tail, bobbing head, and dancing paws.
- Optional live reaction to Spotify's audio energy and rhythmic onsets, processed entirely on your Mac.
- Timed lyric bubbles from [LRCLIB](https://lrclib.net), where a matching recording is available.
- Play/pause, previous/next, seeking, volume, shuffle, and repeat.
- Previous-track button that skips back instead of restarting the current song.
- Directional song-title transitions and left/right arrow keyboard shortcuts.
- Optional always-on-top mode and 15-, 30-, or 60-minute sleep timer.
- Automatic connection to the Spotify Mac app, with connection details tucked into the menu.
- Design preview that works without playing audio.
- Support for macOS Reduce Motion and native transparency settings.

## Requirements

- An **Apple Silicon Mac** running **macOS 13 or later**.
- Apple's Command Line Tools with **Swift 5.10 or later** and the **macOS 14.4 SDK or later**, or a compatible Xcode installation.
- The [Spotify desktop app](https://www.spotify.com/download/mac/), signed in to your account.

The build script currently targets Apple Silicon. Spotify account restrictions still apply; this app controls the desktop client and does not bypass them.

Live beat response requires **macOS 14.2 or later** and system-audio permission. The rest of the player, including gentle animation and lyric bubbles, works on macOS 13 or later.

## Build and run

Install Apple's Command Line Tools if needed:

```sh
xcode-select --install
```

Clone this repository and build the app:

```sh
git clone https://github.com/ananya-1407/tiny-vinyl.git
cd tiny-vinyl/TinyVinyl
./build.sh
open "build/Tiny Vinyl.app"
```

You can also double-click **Launch Tiny Vinyl.command** in Finder. It builds the app if needed, then opens it.

Allow Tiny Vinyl to control Spotify when macOS asks, then choose a song or playlist in Spotify. For live beat response, macOS also asks for system-audio access. Once built, Tiny Vinyl runs independently; you do not need an editor or Codex open.

This is a locally built, ad-hoc-signed app, not a notarized downloadable release. The generated app and build cache are excluded from Git.

## Everyday use

Drag the background to move the player. Pin it above other windows with the pin button. Use the **…** menu for beat sync, lyric bubbles, the sleep timer, Spotify connection details, preview mode, and Quit.

| Control | Action |
| --- | --- |
| Space | Play or pause |
| Left arrow | Previous track |
| Right arrow | Next track |
| Command-Q | Quit Tiny Vinyl; Spotify keeps playing |

Keyboard shortcuts apply while Tiny Vinyl has focus. Opening Tiny Vinyl opens Spotify in the background. If Spotify is quit, the widget stays open; pressing Play opens Spotify again. Opening Spotify separately reconnects an already-running widget. Spotify does not automatically launch Tiny Vinyl.

## How it works

SwiftUI Canvas draws Mochi as separate moving body parts. AppKit provides the floating window and native background blur. A small JavaScript for Automation bridge calls Spotify's local scripting interface through `osascript` to read playback state and send commands. Calls run away from the UI thread.

On macOS 14.2+, a private Core Audio process tap includes only Spotify's audio processes. The app measures sound energy and rhythmic onsets to drive the animation; it does not classify a song's genre or emotional meaning. No microphone, screen capture, audio recording, audio upload, or external audio driver is used. The tap never mutes Spotify and is destroyed when playback pauses, preview mode starts, beat sync is disabled, or the widget quits.

Lyrics are requested from LRCLIB using the current song's title, artist, album, and duration. Only a matching timed LRC response is shown; there are no invented lyrics or estimated timings for untimed text. Coverage and timing depend on the recording. Bubbles clear during lyric gaps and after long lines, and are hidden while paused. Lyrics are held in memory, not bundled in this repository. Turn lyric lookup off in **… → Lyric bubbles**. LRCLIB outages or unavailable lyrics do not interrupt playback.

No Spotify password, API token, or music files are stored in this repository. The app does not use the Spotify Web API, and it does not control Spotify in a browser.

## Project layout

```text
TinyVinyl/
├── Sources/
│   ├── main.swift                 # App lifecycle and translucent window
│   ├── PlayerView.swift           # Player controls and settings
│   ├── CompanionView.swift        # Mochi artwork and animation
│   ├── BeatListener.swift         # Spotify-only Core Audio tap
│   ├── RhythmAnalysis.swift       # Energy and onset detection
│   ├── TimedLyrics.swift          # LRCLIB lookup and LRC timing
│   └── SpotifyController.swift    # Spotify connection and playback state
├── Resources/
│   ├── Info.plist                 # App metadata and permission explanation
│   └── Entitlements.plist         # Apple Events permission
├── build.sh
├── Launch Tiny Vinyl.command
└── README.md                     # More setup and troubleshooting details
```

See [the app guide](TinyVinyl/README.md) for troubleshooting and validation details.

All character artwork is drawn in code, with no external illustration dependencies.

## Validation

Built and signature-checked on an Apple Silicon Mac. Manually verified the compact glass interface, live Spotify metadata and artwork, playback, previous/next controls, automatic connection, and reopening Spotify with Play. The first-time macOS permission flow has not been re-tested on a clean account. Other supported macOS versions have not yet been verified.

For the companion update, verified Mochi's resting/dancing preview and a live LRCLIB timed match. Automated checks cover LRC offsets, repeated timestamps, seeking, Unicode, blank gaps, and synthetic beat/energy response. Live audio-tap validation awaits the Mac's system-audio permission.

Tiny Vinyl is an independent personal project and is not affiliated with Spotify.

Run `./TinyVinyl/test.sh` for the lyric-timing and rhythm-analysis checks. The fixtures use original example text and synthetic audio levels. Optional `./TinyVinyl/test.sh --live-lyrics` checks an actual LRCLIB response without logging lyric text.
