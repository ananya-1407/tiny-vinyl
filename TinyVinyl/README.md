# Tiny Vinyl

A small, native Mac player for Spotify, with a frosted translucent casing and Mochi, an animated cat in headphones. Built with SwiftUI and AppKit; no package installation, API key, or web server required. The casing uses native macOS background blur and respects the system's Reduce Transparency setting.

## Get playing

1. Install [Spotify for Mac](https://www.spotify.com/download/mac/) and sign in.
2. Open **build/Tiny Vinyl.app**, or double-click **Launch Tiny Vinyl.command**.
3. Tiny Vinyl opens Spotify in the background and connects automatically. Allow Tiny Vinyl to control Spotify if macOS asks.
4. Choose a song or playlist in Spotify. Tiny Vinyl shows the current song and controls playback.
5. For live dancing, allow system-audio access when macOS asks. This measures Spotify's audio locally; it never records/uploads audio or accesses the microphone. macOS 14.2+ is required for this feature.

The translucent player is 300 × 510 points. Drag its background to move it and use the pin button to keep it above other windows. The **…** menu includes connection details, reconnect, a sleep timer, a design preview that plays no audio, and Quit. Connection messages stay inside this menu instead of taking space under the controls.

The left button goes directly to the previous song, even when the current song is several seconds in. The right button selects the next song, and track titles slide in the direction of the pressed arrow. Left/right arrow keys do the same when the player has focus; Space toggles playback and ⌘Q quits. Quitting Tiny Vinyl leaves Spotify playing.

If Spotify is closed, pressing Play opens it and resumes playback. If you open Spotify separately, Tiny Vinyl reconnects quietly. It will not repeatedly reopen Spotify after you deliberately quit it.

The widget controls the local Spotify Mac app. Browser playback is not supported. Your Spotify account's playback and skipping restrictions still apply. This personal prototype has no Spotify Web API integration or separate login. Shuffle and repeat reflect the settings exposed by the desktop app; repeat does not select a repeat-one mode.

## Build again

On this Apple Silicon Mac, run:

```sh
cd TinyVinyl
./build.sh
open "build/Tiny Vinyl.app"
```

The build uses Apple's installed command-line tools and ad-hoc signs the app for local use. This is not a notarized distribution build. After rebuilding or moving the app, macOS may ask for Spotify permission again.

## If it needs a nudge

- **Spotify isn't found:** place Spotify in Applications, launch it once, then use **… → Reconnect to Spotify**.
- **Permission denied:** go to **System Settings → Privacy & Security → Automation**, enable Spotify under Tiny Vinyl, then reconnect.
- **No song appears:** start a track in the Spotify Mac app and use this Mac as the playback device.
- **Preview mode:** it is explicitly labeled **Design preview · No audio**. Use **… → Leave design preview** to return to Spotify.

## Files

- `Sources/PlayerView.swift`: the player controls and settings.
- `Sources/CompanionView.swift`: Mochi, the original animated cat character.
- `Sources/BeatListener.swift` and `Sources/RhythmAnalysis.swift`: local Spotify audio energy/onset detection.
- `Sources/TimedLyrics.swift`: LRCLIB requests, caching, and timestamped lyric bubbles.
- `Sources/SpotifyController.swift`: local Spotify scripting, player state, and album artwork.
- `Sources/main.swift`: the floating desktop window and application lifecycle.
- `Resources/Info.plist`: the macOS permission explanation.

Spotify commands run in a background subprocess so the interface stays responsive. No Spotify credentials are collected. Reduce Motion stops dancing and floating-note motion. Beat sync and lyrics can be switched off separately in the **…** menu. If audio permission is unavailable, Mochi uses a gentle animation rather than claiming to follow the beat.

Lyrics come from LRCLIB, which receives the song's title, artist, album, and duration. Real timed lines appear in a small bubble when a matching recording is available. Unavailable lyrics and instrumental gaps show musical notes instead. No lyrics are fabricated or stored in the project.

If beat sync needs permission, use **System Settings → Privacy & Security → Screen & System Audio Recording**, allow Tiny Vinyl's audio access, then choose **… → Retry beat sync**. Keep listening locally through Spotify on this Mac; audio from another Spotify Connect device cannot be analyzed here.

## Validation

Compiled and verified the local app signature. Checked the compact glass layout and absence of the RPM/connection footer in the running app. Verified live Spotify metadata/artwork, playback, next/previous track changes, automatic connection after restarting Tiny Vinyl, and reconnection when Play opens a closed Spotify app. First-time macOS permission prompts were not re-tested because access was already granted on this Mac.

References: [Apple scripting support](https://developer.apple.com/documentation/foundation/scripting-support), [Apple automation permission](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription).

The companion update builds successfully. Resting/dancing poses and a live LRCLIB timed match were verified. Run `./test.sh` to check lyric timing and synthetic rhythm response. Live audio-tap validation awaits system-audio permission. Audio tap implementation follows [Apple's Core Audio documentation](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps); lyric requests follow [LRCLIB's API documentation](https://lrclib.net/docs).
