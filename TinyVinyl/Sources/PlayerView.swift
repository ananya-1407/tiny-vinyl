import SwiftUI

private let ink = Color(red: 0.20, green: 0.19, blue: 0.16)
private let muted = Color(red: 0.51, green: 0.48, blue: 0.42)
private let paper = Color(red: 0.95, green: 0.92, blue: 0.86)
private let rust = Color(red: 0.73, green: 0.29, blue: 0.16)

enum PlayerLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 510
    static let padding: CGFloat = 16
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var beats: BeatListener
    @ObservedObject var lyrics: LyricsModel
    @State private var volume = 50.0
    @State private var seeking = false
    @State private var changingVolume = false
    @State private var position = 0.0

    init(model: PlayerModel) {
        self.model = model
        self.beats = model.beats
        self.lyrics = model.lyrics
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            CompanionView(model: model, beats: beats, lyrics: lyrics)
                .padding(.top, 12)
            HStack(spacing: 6) {
                Circle().fill(model.connected || model.preview ? rust : muted.opacity(0.6)).frame(width: 5, height: 5)
                Text(model.status).font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.5)
                Spacer()
            }.padding(.top, 13)
            songDetails.padding(.top, 8)
            progress.padding(.top, 10)
            controls.padding(.top, 8)
            footer.padding(.top, 10)
        }
        .padding(PlayerLayout.padding)
        .frame(width: PlayerLayout.width, height: PlayerLayout.height, alignment: .top)
        .background(paper.opacity(0.20))
        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 23))
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .onChange(of: model.playback.volume) { if !changingVolume { volume = $0 } }
        .onChange(of: model.playback.position) { if !seeking { position = $0 } }
        .onAppear { volume = model.playback.volume; position = model.playback.position }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                Image(systemName: "pawprint.fill").font(.system(size: 16))
                Text("tiny vinyl").font(.system(size: 18, weight: .semibold, design: .serif))
            }
            Spacer()
            Button { model.pinned.toggle() } label: {
                Image(systemName: model.pinned ? "pin.fill" : "pin").font(.system(size: 12))
                    .foregroundStyle(model.pinned ? rust : muted).frame(width: 24, height: 24)
            }.buttonStyle(.plain).help(model.pinned ? "Unpin from above other windows" : "Keep above other windows")
                .accessibilityLabel(model.pinned ? "Unpin player" : "Pin player on top")
            Menu {
                if !model.message.isEmpty && !model.preview {
                    Text(model.message)
                    Divider()
                }
                Button(model.preview ? "Leave design preview" : "Try design preview") { model.togglePreview() }
                Button("Open Spotify") { model.openSpotify() }
                Button(model.connected ? "Reconnect to Spotify" : "Connect Spotify") { model.connect() }.disabled(model.busy)
                Divider()
                Toggle("Dance to Spotify audio", isOn: $beats.enabled)
                Text(beats.status)
                Button("Retry beat sync") { beats.retry() }
                Divider()
                Toggle("Lyric bubbles", isOn: $lyrics.enabled)
                Text(lyrics.status)
                Button("About lyrics · LRCLIB") { NSWorkspace.shared.open(URL(string: "https://lrclib.net")!) }
                Divider()
                Menu("Sleep timer") {
                    ForEach([15, 30, 60], id: \.self) { minutes in
                        Button("Pause after \(minutes) minutes") { model.sleepUntil = Date().addingTimeInterval(Double(minutes * 60)) }
                    }
                    Button("Cancel timer") { model.sleepUntil = nil }
                }.disabled(!model.connected && !model.preview)
                Divider()
                Button("Quit Tiny Vinyl", action: { NSApp.terminate(nil) }).keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).frame(width: 20, height: 24)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Player options")
        }.frame(height: 24)
    }

    private var songDetails: some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.playback.name)
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                    .lineLimit(1).help(model.playback.name)
                Text(model.playback.artist).font(.system(size: 10)).foregroundStyle(muted)
                    .lineLimit(1).help(model.playback.artist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(model.playback.id.isEmpty ? model.playback.name : model.playback.id)
            .transition(.asymmetric(
                insertion: .move(edge: model.skipDirection < 0 ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: model.skipDirection < 0 ? .leading : .trailing).combined(with: .opacity)))
        }
        .frame(height: 42, alignment: .leading)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: model.playback.id.isEmpty ? model.playback.name : model.playback.id)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(value: $position, in: 0...max(1, model.playback.duration), onEditingChanged: { editing in
                seeking = editing
                if !editing { model.action(.seek(position)) }
            }).tint(rust).controlSize(.mini).disabled(!model.canControl || model.playback.duration <= 0)
                .accessibilityLabel("Song position")
            HStack {
                Text(time(position))
                Spacer()
                Text(time(model.playback.duration))
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            control("shuffle", "Shuffle", active: model.playback.shuffle) { model.action(.shuffle(!model.playback.shuffle)) }
            Spacer()
            control("backward.end.fill", "Previous song", size: 19) { model.action(.previous) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Spacer()
            Button { model.action(.toggle) } label: {
                Image(systemName: model.playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .offset(x: model.playback.playing ? 0 : 1)
                    .foregroundStyle(paper).frame(width: 46, height: 46)
                    .background(ink, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 2))
            }.buttonStyle(.plain).disabled(!model.canUseTransport)
                .opacity(model.spotifyInstalled || model.preview ? 1 : 0.4)
                .help(model.playback.playing ? "Pause" : "Play")
                .accessibilityLabel(model.playback.playing ? "Pause" : "Play")
                .keyboardShortcut(.space, modifiers: [])
            Spacer()
            control("forward.end.fill", "Next song", size: 19) { model.action(.next) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Spacer()
            control("repeat", "Repeat", active: model.playback.repeating) { model.action(.repeatTrack(!model.playback.repeating)) }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(muted)
            Slider(value: $volume, in: 0...100, onEditingChanged: { editing in
                changingVolume = editing
                if !editing { model.action(.volume(volume)) }
            }).tint(muted).controlSize(.mini).disabled(!model.canControl).accessibilityLabel("Spotify volume")
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(muted)
            Rectangle().fill(muted.opacity(0.25)).frame(width: 1, height: 13).padding(.horizontal, 4)
            if let until = model.sleepUntil {
                Button { model.sleepUntil = nil } label: {
                    Image(systemName: "moon.zzz.fill").foregroundStyle(rust).font(.system(size: 12))
                }.buttonStyle(.plain).help("Sleep timer ends at \(until.formatted(date: .omitted, time: .shortened)). Click to cancel.")
            } else {
                Image(systemName: "heart").font(.system(size: 10)).foregroundStyle(muted).accessibilityLabel("Your music companion")
            }
        }.frame(height: 17)
    }

    private func control(_ symbol: String, _ title: String, size: CGFloat = 14, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? rust : ink).frame(width: 32, height: 36)
                .opacity(model.spotifyInstalled || model.preview ? 1 : 0.3)
        }.buttonStyle(.plain).disabled(!model.canUseTransport).help(title).accessibilityLabel(title)
    }

    private func time(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.isFinite ? seconds : 0))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
