# Tiny Vinyl

A tiny, translucent Spotify player for your Mac. A walnut turntable, a spinning record, and just enough controls to keep the music going.

Built with **SwiftUI + AppKit**. Runs locally without a web server, Spotify API key, or separate account login.

## Features

- Compact, draggable **300 × 510** frosted-glass window.
- Vinyl record that spins during playback, with album artwork on the label.
- Play/pause, previous/next, seeking, volume, shuffle, and repeat.
- Previous-track button that skips back instead of restarting the current song.
- Directional song-title transitions and left/right arrow keyboard shortcuts.
- Optional always-on-top mode and 15-, 30-, or 60-minute sleep timer.
- Automatic connection to the Spotify Mac app, with connection details tucked into the menu.
- Design preview that works without playing audio.
- Support for macOS Reduce Motion and native transparency settings.

## Requirements

- An **Apple Silicon Mac** running **macOS 13 or later**.
- Apple's Command Line Tools with **Swift 5.10 or later**, or a compatible Xcode installation.
- The [Spotify desktop app](https://www.spotify.com/download/mac/), signed in to your account.

The build script currently targets Apple Silicon. Spotify account restrictions still apply; this app controls the desktop client and does not bypass them.

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

Allow Tiny Vinyl to control Spotify when macOS asks, then choose a song or playlist in Spotify. Once built, Tiny Vinyl runs independently; you do not need an editor or Codex open.

This is a locally built, ad-hoc-signed app, not a notarized downloadable release. The generated app and build cache are excluded from Git.

## Everyday use

Drag the background to move the player. Pin it above other windows with the pin button. Use the **…** menu for the sleep timer, Spotify connection details, preview mode, and Quit.

| Control | Action |
| --- | --- |
| Space | Play or pause |
| Left arrow | Previous track |
| Right arrow | Next track |
| Command-Q | Quit Tiny Vinyl; Spotify keeps playing |

Keyboard shortcuts apply while Tiny Vinyl has focus. Opening Tiny Vinyl opens Spotify in the background. If Spotify is quit, the widget stays open; pressing Play opens Spotify again. Opening Spotify separately reconnects an already-running widget. Spotify does not automatically launch Tiny Vinyl.

## How it works

SwiftUI draws the player, record, and controls. AppKit provides the floating window and native background blur. A small JavaScript for Automation bridge calls Spotify's local scripting interface through `osascript` to read playback state and send commands. Calls run away from the UI thread. Artwork is fetched over HTTPS from the URL supplied by Spotify.

No Spotify password, API token, or music files are stored in this repository. The app does not use the Spotify Web API, and it does not control Spotify in a browser.

## Project layout

```text
TinyVinyl/
├── Sources/
│   ├── main.swift                 # App lifecycle and translucent window
│   ├── PlayerView.swift           # Turntable, animations, and controls
│   └── SpotifyController.swift    # Spotify connection and playback state
├── Resources/
│   ├── Info.plist                 # App metadata and permission explanation
│   └── Entitlements.plist         # Apple Events permission
├── build.sh
├── Launch Tiny Vinyl.command
└── README.md                     # More setup and troubleshooting details
```

See [the app guide](TinyVinyl/README.md) for troubleshooting and validation details.

## Validation

Built and signature-checked on an Apple Silicon Mac. Manually verified the compact glass interface, live Spotify metadata and artwork, playback, previous/next controls, automatic connection, and reopening Spotify with Play. The first-time macOS permission flow has not been re-tested on a clean account. Other supported macOS versions have not yet been verified.

Tiny Vinyl is an independent personal project and is not affiliated with Spotify.
