import Cocoa
import SwiftUI

struct Playback: Decodable {
    var name: String = "Your next little obsession."
    var artist: String = "A home for whatever’s on repeat."
    var id: String = ""
    var artwork: String = ""
    var playing: Bool = false
    var duration: Double = 0
    var position: Double = 0
    var volume: Double = 50
    var shuffle: Bool = false
    var repeating: Bool = false
}

enum SpotifyAction {
    case toggle, next, previous, shuffle(Bool), repeatTrack(Bool), volume(Double), seek(Double), pause

    var script: String {
        switch self {
        case .toggle: return "s.playpause();"
        case .next: return "s.nextTrack();"
        // Spotify normally restarts a song after a few seconds. Seeking to the start
        // first makes the left arrow consistently select the previous track instead.
        case .previous: return "s.playerPosition = 0; s.previousTrack();"
        case .shuffle(let value): return "s.shuffling = \(value);"
        case .repeatTrack(let value): return "s.repeating = \(value);"
        case .volume(let value): return "s.soundVolume = \(Int(min(100, max(0, value))));"
        case .seek(let value): return "s.playerPosition = \(max(0, value));"
        case .pause: return "s.pause();"
        }
    }
}

// A subprocess keeps Spotify requests and the macOS permission dialog off the UI thread.
// Only fixed commands and bounded numbers enter the script, never track text or user input.
enum SpotifyBridge {
    static let snapshot = """
    const s = Application('com.spotify.client');
    const state = s.playerState();
    let p = {name:'Pick a song in Spotify', artist:'Your record is ready when you are.',
      id:'', artwork:'', playing:state === 'playing', duration:0, position:0,
      volume:s.soundVolume(), shuffle:s.shuffling(), repeating:s.repeating()};
    try {
      const t = s.currentTrack();
      p.name = t.name() || p.name; p.artist = t.artist() || '';
      p.id = t.id() || ''; p.duration = Math.max(0, t.duration() / 1000);
      p.position = Math.max(0, s.playerPosition());
      try { p.artwork = t.artworkUrl() || ''; } catch (_) {}
    } catch (_) {}
    JSON.stringify(p);
    """

    static func run(_ script: String, timeout: TimeInterval = 10) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-l", "JavaScript", "-e", script]
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                    // Responses are a small JSON object; reading stdout while running also drains the pipe.
                    let data = output.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    deadline.cancel()
                    guard process.terminationStatus == 0 else {
                        let detail = String(data: errorData, encoding: .utf8) ?? "Spotify did not respond."
                        throw NSError(domain: "TinyVinyl.Spotify", code: Int(process.terminationStatus),
                                      userInfo: [NSLocalizedDescriptionKey: detail])
                    }
                    continuation.resume(returning: data)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published var playback = Playback()
    @Published var artwork: NSImage?
    @Published var connected = false
    @Published var busy = false
    @Published var preview = false
    @Published var skipDirection = 1
    @Published var message = "Connect Spotify to give this record a spin."
    @Published var sleepUntil: Date?
    @Published var pinned = UserDefaults.standard.bool(forKey: "keepOnTop") {
        didSet {
            UserDefaults.standard.set(pinned, forKey: "keepOnTop")
            NSApp.windows.filter { $0.identifier?.rawValue == "player" }.forEach {
                $0.level = pinned ? .floating : .normal
            }
        }
    }
    private var pollTask: Task<Void, Never>?
    private var artTask: Task<Void, Never>?
    private var artworkURL = ""
    private var generation = 0
    private var stateRevision = 0
    private var previewIndex = 0
    private var lastTick = Date()
    private var nextReconnect = Date.distantPast
    private var permissionDenied = false

    var spotifyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
    }
    var spotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }
    var canControl: Bool { (connected || preview) && !busy }
    var canUseTransport: Bool { (connected || preview || spotifyInstalled) && !busy }
    var status: String {
        if preview { return "DESIGN PREVIEW · NO AUDIO" }
        if busy && !connected { return "GETTING THE RECORD READY" }
        if !connected { return "A LITTLE ROOM FOR MUSIC" }
        return playback.playing ? "NOW SPINNING · SPOTIFY" : "TAKE YOUR TIME · PAUSED"
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.tick()
            }
        }
        if !preview, spotifyInstalled { connect(userInitiated: false) }
    }

    func connect(userInitiated: Bool = true, afterConnecting pendingAction: SpotifyAction? = nil) {
        guard !busy else { return }
        if userInitiated { permissionDenied = false }
        generation += 1
        preview = false
        connected = false
        playback = Playback()
        artwork = nil
        artworkURL = ""
        if !spotifyInstalled {
            message = "Install the Spotify Mac app, then come back and connect."
            if userInitiated { NSWorkspace.shared.open(URL(string: "https://www.spotify.com/download/mac/")!) }
            return
        }
        busy = true
        message = "Allow Tiny Vinyl to control Spotify when macOS asks."
        let current = generation
        Task {
            do {
                if !spotifyRunning,
                   let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        let configuration = NSWorkspace.OpenConfiguration()
                        configuration.activates = false
                        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                            if let error { continuation.resume(throwing: error) }
                            else { continuation.resume() }
                        }
                    }
                    try await Task.sleep(nanoseconds: 1_500_000_000)
                }
                let data = try await SpotifyBridge.run(SpotifyBridge.snapshot, timeout: 120)
                guard current == generation else { return }
                apply(try JSONDecoder().decode(Playback.self, from: data))
                connected = true
                permissionDenied = false
                UserDefaults.standard.set(true, forKey: "spotifyConnected")
                message = ""
            } catch { if current == generation { report(error) } }
            if current == generation {
                busy = false
                if connected, let pendingAction { action(pendingAction) }
            }
        }
    }

    private func tick() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        if let until = sleepUntil, now >= until {
            // Retry next tick if a command is in flight; don't drop the pause request.
            if !busy {
                sleepUntil = nil
                action(.pause)
            }
        }
        if preview {
            if playback.playing { playback.position = min(playback.duration, playback.position + elapsed) }
            if playback.position >= playback.duration { demoSong(offset: 1) }
            return
        }
        guard !busy else { return }
        if !connected {
            // Reattach quietly when Spotify is reopened; don't keep reopening it
            // after the user deliberately quits it, or repeat a denied permission prompt.
            if spotifyRunning && !permissionDenied && now >= nextReconnect {
                nextReconnect = now.addingTimeInterval(8)
                connect(userInitiated: false)
            }
            return
        }
        guard spotifyRunning else {
            connected = false
            playback.playing = false
            message = "Spotify is closed. Connect to open it again."
            return
        }
        let current = generation
        let revision = stateRevision
        do {
            let data = try await SpotifyBridge.run(SpotifyBridge.snapshot)
            // A playback command may finish while this read is in flight.
            // Discard that older read instead of jumping the UI back a song.
            guard current == generation, revision == stateRevision else { return }
            apply(try JSONDecoder().decode(Playback.self, from: data))
        } catch { if current == generation, revision == stateRevision { report(error) } }
    }

    func action(_ action: SpotifyAction) {
        if !connected && !preview && !busy {
            connect(afterConnecting: action)
            return
        }
        guard canControl else { return }
        switch action {
        case .previous: skipDirection = -1
        case .next: skipDirection = 1
        default: break
        }
        if preview {
            switch action {
            case .toggle: playback.playing.toggle()
            case .pause: playback.playing = false
            case .next: demoSong(offset: 1)
            case .previous: demoSong(offset: -1)
            case .shuffle(let value): playback.shuffle = value
            case .repeatTrack(let value): playback.repeating = value
            case .volume(let value): playback.volume = value
            case .seek(let value): playback.position = min(playback.duration, max(0, value))
            }
            return
        }
        stateRevision += 1
        busy = true
        let current = generation
        Task {
            do {
                _ = try await SpotifyBridge.run("const s = Application('com.spotify.client'); " + action.script)
                let data = try await SpotifyBridge.run(SpotifyBridge.snapshot)
                guard current == generation else { return }
                apply(try JSONDecoder().decode(Playback.self, from: data))
                message = ""
            } catch { if current == generation { report(error) } }
            if current == generation { busy = false }
        }
    }

    func togglePreview() {
        generation += 1
        busy = false
        connected = false
        preview.toggle()
        sleepUntil = nil
        artwork = nil
        artworkURL = ""
        artTask?.cancel()
        if preview {
            demoSong(offset: 0)
            message = "Preview mode — controls animate; no music plays."
        } else {
            playback = Playback()
            message = "Connect Spotify to give this record a spin."
        }
    }

    private func demoSong(offset: Int) {
        let songs = [("Midnight grooves", "Side A · The living room sessions"),
                     ("A slower kind of Sunday", "Side B · The living room sessions"),
                     ("Just one more record", "Side C · The living room sessions")]
        previewIndex = (previewIndex + offset + songs.count) % songs.count
        playback = Playback(name: songs[previewIndex].0, artist: songs[previewIndex].1,
                            id: "preview-\(previewIndex)", playing: true, duration: 228, position: 42,
                            volume: playback.volume, shuffle: playback.shuffle, repeating: playback.repeating)
    }

    private func apply(_ value: Playback) {
        playback = value
        playback.position = min(playback.duration, max(0, playback.position))
        guard value.artwork != artworkURL else { return }
        artworkURL = value.artwork
        artwork = nil
        artTask?.cancel()
        guard let url = URL(string: value.artwork), url.scheme == "https" else { return }
        artTask = Task { [weak self] in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled, let self,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      data.count < 10_000_000, self.artworkURL == url.absoluteString else { return }
                self.artwork = NSImage(data: data)
            } catch { /* The printed label remains visible if artwork cannot load. */ }
        }
    }

    private func report(_ error: Error) {
        let detail = error.localizedDescription
        connected = false
        nextReconnect = Date().addingTimeInterval(8)
        playback.playing = false
        if detail.contains("1743") || detail.lowercased().contains("not authorized") {
            permissionDenied = true
            message = "Allow Spotify in System Settings → Privacy & Security → Automation, then reconnect."
        } else {
            message = "Couldn’t reach Spotify. Open the Mac app, pick a song, then reconnect."
        }
        NSLog("Tiny Vinyl Spotify: %@", detail)
    }

    func openSpotify() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        } else { NSWorkspace.shared.open(URL(string: "https://www.spotify.com/download/mac/")!) }
    }
}
