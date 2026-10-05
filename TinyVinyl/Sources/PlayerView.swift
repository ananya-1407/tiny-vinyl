import SwiftUI

private let ink = Color(red: 0.20, green: 0.19, blue: 0.16)
private let muted = Color(red: 0.51, green: 0.48, blue: 0.42)
private let paper = Color(red: 0.95, green: 0.92, blue: 0.86)
private let rust = Color(red: 0.73, green: 0.29, blue: 0.16)

enum PlayerLayout {
    static let width: CGFloat = 300
    static let height: CGFloat = 510
    static let padding: CGFloat = 16
    static let turntableScale = (width - padding * 2) / 292
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @State private var volume = 50.0
    @State private var seeking = false
    @State private var changingVolume = false
    @State private var position = 0.0

    var body: some View {
        VStack(spacing: 0) {
            header
            TurntableView(playing: model.playback.playing, artwork: model.artwork)
                .scaleEffect(PlayerLayout.turntableScale)
                .frame(width: 268, height: 248 * PlayerLayout.turntableScale)
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
                Image(systemName: "opticaldisc.fill").font(.system(size: 17))
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
                Text("SIDE A").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(muted)
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

struct TurntableView: View {
    let playing: Bool
    let artwork: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle = 0.0
    @State private var lastFrame = Date()
    private let frames = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(colors: [Color(red: 0.39, green: 0.24, blue: 0.15), Color(red: 0.25, green: 0.15, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Canvas { context, size in
                for index in 0..<85 {
                    var grain = Path()
                    let y = CGFloat(index) * 3
                    grain.move(to: CGPoint(x: 0, y: y))
                    grain.addCurve(to: CGPoint(x: size.width, y: y + 2), control1: CGPoint(x: 90, y: y - 6), control2: CGPoint(x: 180, y: y + 7))
                    context.stroke(grain, with: .color(.black.opacity(index % 3 == 0 ? 0.10 : 0.035)), lineWidth: 1)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 15))
            RoundedRectangle(cornerRadius: 11).strokeBorder(.black.opacity(0.2), lineWidth: 1).padding(5)
            Circle().fill(.black.opacity(0.35)).frame(width: 225, height: 225).offset(x: -13, y: 3).blur(radius: 3)
            Circle().fill(Color(white: 0.55)).frame(width: 219, height: 219).offset(x: -15)
            record.frame(width: 210, height: 210).rotationEffect(.degrees(angle)).offset(x: -15)
            tonearm
            HStack {
                Circle().fill(playing ? Color(red: 1, green: 0.48, blue: 0.22) : Color(red: 0.4, green: 0.2, blue: 0.14))
                    .frame(width: 4, height: 4).shadow(color: playing ? .orange : .clear, radius: 3)
                Text("STEREO").font(.system(size: 6, weight: .medium, design: .monospaced)).tracking(1.2).foregroundStyle(paper.opacity(0.45))
            }.position(x: 35, y: 232)
            ForEach(0..<4, id: \.self) { index in
                // Top and bottom screws are cosmetic; positions form the turntable chassis.
                Circle().fill(.black.opacity(0.4)).frame(width: 3, height: 3)
                    .position(x: index % 2 == 0 ? 11 : 281, y: index < 2 ? 11 : 237)
            }
        }
        .frame(width: 292, height: 248)
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: ink.opacity(0.22), radius: 8, x: 0, y: 5)
        .onReceive(frames) { now in
            guard playing && !reduceMotion else { return }
            let elapsed = min(0.1, now.timeIntervalSince(lastFrame))
            lastFrame = now
            angle = (angle + elapsed * 36).truncatingRemainder(dividingBy: 360)
        }
        .onChange(of: playing) { _ in lastFrame = Date() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(playing ? "Spinning vinyl record" : "Vinyl record at rest")
    }

    private var record: some View {
        ZStack {
            Circle().fill(Color(white: 0.075))
            Circle().fill(AngularGradient(stops: [
                .init(color: .white.opacity(0.01), location: 0),
                .init(color: .white.opacity(0.17), location: 0.13),
                .init(color: .black.opacity(0.3), location: 0.24),
                .init(color: .white.opacity(0.02), location: 0.49),
                .init(color: .white.opacity(0.15), location: 0.65),
                .init(color: .black.opacity(0.25), location: 0.8),
                .init(color: .white.opacity(0.01), location: 1)
            ], center: .center))
            ForEach(0..<28, id: \.self) { ring in
                Circle().strokeBorder(.white.opacity(ring % 4 == 0 ? 0.16 : 0.065), lineWidth: 0.55)
                    .padding(CGFloat(ring) * 2.05 + 7)
            }
            Circle().fill(rust).frame(width: 77, height: 77)
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill().frame(width: 77, height: 77).clipShape(Circle())
            } else {
                VStack(spacing: 4) {
                    Text("TINY VINYL").font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1)
                    Rectangle().fill(paper.opacity(0.6)).frame(width: 43, height: 0.5)
                    Text("LONG PLAY").font(.system(size: 5, design: .monospaced)).tracking(1.4)
                    Spacer().frame(height: 12)
                    Text("STEREO").font(.system(size: 4.5, design: .monospaced))
                }.foregroundStyle(paper).frame(height: 53)
            }
            Circle().strokeBorder(.black.opacity(0.2), lineWidth: 1).frame(width: 77, height: 77)
            Circle().fill(paper.opacity(0.8)).frame(width: 9, height: 9)
            Circle().fill(Color(white: 0.2)).frame(width: 4, height: 4)
        }
    }

    private var tonearm: some View {
        ZStack(alignment: .top) {
            Circle().fill(.black.opacity(0.25)).frame(width: 27, height: 27).offset(y: 2)
            Circle().fill(LinearGradient(colors: [Color(white: 0.70), Color(white: 0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 21, height: 21)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.45), Color(white: 0.8)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: 145).offset(y: 7)
                RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.16)).frame(width: 13, height: 26).offset(y: 137)
                Rectangle().fill(rust).frame(width: 13, height: 4).offset(y: 156)
            }.frame(width: 28, height: 168, alignment: .top)
                .rotationEffect(.degrees(playing ? 25 : 5), anchor: .top)
                .animation(.easeInOut(duration: 0.8), value: playing)
            Circle().fill(Color(white: 0.23)).frame(width: 7, height: 7).offset(y: 7)
        }.frame(width: 28, height: 175, alignment: .top).position(x: 256, y: 113)
            .shadow(color: .black.opacity(0.4), radius: 2, x: 2, y: 2)
    }
}
