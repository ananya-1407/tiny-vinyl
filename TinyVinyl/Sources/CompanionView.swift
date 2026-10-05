import SwiftUI

private let fur = Color(red: 1, green: 0.94, blue: 0.81)
private let outline = Color(red: 0.31, green: 0.25, blue: 0.26)
private let rose = Color(red: 0.89, green: 0.53, blue: 0.57)
private let lavender = Color(red: 0.64, green: 0.61, blue: 0.82)

struct CompanionView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var beats: BeatListener
    @ObservedObject var lyrics: LyricsModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let now = timeline.date
            let playing = model.playback.playing
            let time = now.timeIntervalSinceReferenceDate
            let live = beats.active && beats.receivingAudio && !model.preview
            let energy = playing && !reduceMotion ? (live ? beats.frame.energy : 0.32) : 0
            let pulse = playing ? (live ? beats.frame.pulse : max(0, sin(time * 5)) * 0.25) : 0
            let tempo = live ? beats.frame.tempo : 90
            let line = lyrics.timed?.current(at: model.position(at: now))
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [Color(red: 0.90, green: 0.87, blue: 0.96).opacity(0.72),
                                                   Color(red: 0.98, green: 0.90, blue: 0.85).opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(.white.opacity(0.24)).frame(width: 165).blur(radius: 7).offset(y: 46)
                Canvas { context, size in
                    let rhythm = reduceMotion ? 0 : time * tempo / 60 * .pi
                    let sway = playing && !reduceMotion ? sin(rhythm) : 0
                    let bounce = playing && !reduceMotion ? abs(sin(rhythm * 2)) * (1.4 + energy * 3) + pulse * 5 : 0
                    let breathing = reduceMotion ? 0 : sin(time * 1.6) * 0.6
                    let shadowWidth = 85 - bounce * 1.1
                    context.fill(Path(ellipseIn: CGRect(x: 134 - shadowWidth / 2, y: 207, width: shadowWidth, height: 9)), with: .color(outline.opacity(0.12)))
                    drawNotes(in: &context, time: reduceMotion ? 0 : time, playing: playing, energy: energy)
                    var character = context
                    character.translateBy(x: 134 + sway * (2 + energy * 3), y: 129 - bounce + breathing)
                    character.scaleBy(x: 0.91, y: 0.91)
                    character.rotate(by: .degrees(sway * (1.5 + energy * 3)))
                    drawCat(in: &character, time: time, sway: sway, pulse: reduceMotion ? 0 : pulse,
                            energy: energy, playing: playing, reduceMotion: reduceMotion)
                }
                if let line, playing {
                    Text(line.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(outline)
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .frame(maxWidth: 242)
                        .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(alignment: .bottom) {
                            Triangle().fill(.white.opacity(0.85)).frame(width: 10, height: 6).offset(x: 30, y: 5)
                        }
                        .padding(.top, 6)
                        .id(line.time)
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 3)))
                } else if !playing {
                    Text("a little pause, a little peace")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(outline.opacity(0.55)).padding(.top, 13)
                }
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").font(.system(size: 6))
                        Text("mochi").font(.system(size: 8, weight: .medium, design: .rounded)).tracking(1)
                        Spacer()
                        if playing && live {
                            HStack(alignment: .center, spacing: 2) {
                                ForEach(0..<4, id: \.self) { index in
                                    Capsule().frame(width: 2, height: reduceMotion ? 5 : 3 + energy * Double(4 + index * 2))
                                }
                            }.frame(height: 12).accessibilityLabel("Reacting to Spotify audio")
                        }
                    }.foregroundStyle(outline.opacity(0.42)).padding(.horizontal, 12).padding(.bottom, 9)
                }
            }
            .frame(width: 268, height: 228)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: line?.time)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(playing ? "Mochi the cat dancing\(live ? " to Spotify’s audio" : " gently")" : "Mochi the cat resting")
            .accessibilityValue(line?.text ?? "")
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: rect.width, y: 0)); p.addLine(to: CGPoint(x: rect.midX, y: rect.height)); p.closeSubpath() }
    }
}

private func stroke(_ path: Path, in context: inout GraphicsContext, color: Color = outline, width: CGFloat = 2) {
    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

private func shape(_ path: Path, in context: inout GraphicsContext, fill: Color, width: CGFloat = 1.8) {
    context.fill(path, with: .color(fill))
    stroke(path, in: &context, width: width)
}

private func roundRect(_ rect: CGRect, radius: CGFloat) -> Path {
    Path(roundedRect: rect, cornerRadius: radius)
}

private func drawCat(in context: inout GraphicsContext, time: Double, sway: Double, pulse: Double,
                     energy: Double, playing: Bool, reduceMotion: Bool) {
    // A soft, curling tail stays behind the body and swishes with the music.
    var tail = Path()
    tail.move(to: CGPoint(x: 22, y: 49))
    tail.addCurve(to: CGPoint(x: 51 + sway * 4, y: 22 - energy * 6),
                  control1: CGPoint(x: 72, y: 75), control2: CGPoint(x: 76 + sway * 4, y: 12))
    stroke(tail, in: &context, width: 13)
    stroke(tail, in: &context, color: fur, width: 9)

    // Little legs, chunky sneakers, and alternating toe taps.
    for side in [-1.0, 1.0] {
        var foot = context
        foot.translateBy(x: side * 14, y: 60)
        foot.rotate(by: .degrees(playing ? side * max(0, sway * side) * (8 + energy * 10) : side * 5))
        shape(roundRect(CGRect(x: -10, y: -4, width: 20, height: 29), radius: 8), in: &foot,
              fill: Color(red: 0.35, green: 0.36, blue: 0.45))
        shape(roundRect(CGRect(x: -13, y: 16, width: 28, height: 14), radius: 7), in: &foot, fill: Color(red: 1, green: 0.97, blue: 0.92))
        var sole = Path(); sole.move(to: CGPoint(x: -10, y: 26)); sole.addLine(to: CGPoint(x: 12, y: 26))
        stroke(sole, in: &foot, color: outline.opacity(0.45), width: 1)
    }

    // Oversized hoodie and a small heart patch.
    var hoodie = Path()
    hoodie.move(to: CGPoint(x: -23, y: 3))
    hoodie.addQuadCurve(to: CGPoint(x: 24, y: 3), control: CGPoint(x: 0, y: -5))
    hoodie.addQuadCurve(to: CGPoint(x: 33, y: 51), control: CGPoint(x: 35, y: 27))
    hoodie.addQuadCurve(to: CGPoint(x: -32, y: 51), control: CGPoint(x: 0, y: 65))
    hoodie.addQuadCurve(to: CGPoint(x: -23, y: 3), control: CGPoint(x: -35, y: 27))
    shape(hoodie, in: &context, fill: lavender)
    var pocket = Path(); pocket.move(to: CGPoint(x: -16, y: 36)); pocket.addQuadCurve(to: CGPoint(x: 16, y: 36), control: CGPoint(x: 0, y: 44))
    stroke(pocket, in: &context, color: outline.opacity(0.35), width: 1.2)
    context.draw(Text("♥").font(.system(size: 11)).foregroundColor(Color(red: 1, green: 0.87, blue: 0.79)), at: CGPoint(x: 0, y: 26))
    for side in [-1.0, 1.0] {
        var string = Path(); string.move(to: CGPoint(x: side * 7, y: 8)); string.addLine(to: CGPoint(x: side * 9, y: 20))
        stroke(string, in: &context, color: .white.opacity(0.65), width: 1.5)
        var arm = context
        arm.translateBy(x: side * 26, y: 11)
        let lift = playing ? 12 + energy * 32 + pulse * 22 + max(0, sway * side) * 13 : 7
        arm.rotate(by: .degrees(-side * lift))
        shape(roundRect(CGRect(x: -10, y: 0, width: 20, height: 31), radius: 9), in: &arm, fill: lavender)
        shape(Path(ellipseIn: CGRect(x: -8, y: 23, width: 16, height: 16)), in: &arm, fill: fur, width: 1.5)
    }

    var head = context
    head.translateBy(x: 0, y: playing ? -pulse * 2 : 0)
    head.rotate(by: .degrees(playing ? sway * (3 + energy * 4) : -4))

    // Cat ears, each with a pink inner ear.
    for side in [-1.0, 1.0] {
        var ear = Path()
        ear.move(to: CGPoint(x: side * 43, y: -39))
        ear.addQuadCurve(to: CGPoint(x: side * 37, y: -78), control: CGPoint(x: side * 44, y: -74))
        ear.addQuadCurve(to: CGPoint(x: side * 15, y: -49), control: CGPoint(x: side * 24, y: -72))
        ear.closeSubpath()
        shape(ear, in: &head, fill: fur)
        var inner = Path()
        inner.move(to: CGPoint(x: side * 36, y: -50)); inner.addLine(to: CGPoint(x: side * 35, y: -67)); inner.addLine(to: CGPoint(x: side * 25, y: -51)); inner.closeSubpath()
        head.fill(inner, with: .color(rose.opacity(0.62)))
    }

    shape(Path(ellipseIn: CGRect(x: -46, y: -57, width: 92, height: 73)), in: &head, fill: fur, width: 2)
    // Cream shading and tufts keep the face soft at small sizes.
    head.fill(Path(ellipseIn: CGRect(x: -37, y: -3, width: 74, height: 15)), with: .color(.white.opacity(0.24)))
    for side in [-1.0, 1.0] {
        head.fill(Path(ellipseIn: CGRect(x: side * 29 - 9, y: -13, width: 18, height: 10)), with: .color(rose.opacity(0.40)))
        let eyeX = side * 18
        let blink = !reduceMotion && time.truncatingRemainder(dividingBy: 6.7) < 0.16
        if playing || blink {
            var eye = Path(); eye.move(to: CGPoint(x: eyeX - 6, y: -22))
            eye.addQuadCurve(to: CGPoint(x: eyeX + 6, y: -22), control: CGPoint(x: eyeX, y: playing ? -29 : -18))
            stroke(eye, in: &head, width: 2.7)
        } else {
            head.fill(Path(ellipseIn: CGRect(x: eyeX - 3, y: -27, width: 6, height: 8)), with: .color(outline))
            head.fill(Path(ellipseIn: CGRect(x: eyeX - 1, y: -26, width: 2, height: 2)), with: .color(.white))
        }
        for index in 0..<2 {
            var whisker = Path()
            whisker.move(to: CGPoint(x: side * 35, y: -7 + Double(index) * 5))
            whisker.addLine(to: CGPoint(x: side * 45, y: -10 + Double(index) * 8))
            stroke(whisker, in: &head, color: outline.opacity(0.48), width: 1)
        }
    }
    var nose = Path(); nose.move(to: CGPoint(x: -3, y: -14)); nose.addQuadCurve(to: CGPoint(x: 3, y: -14), control: CGPoint(x: 0, y: -16)); nose.addLine(to: CGPoint(x: 0, y: -10)); nose.closeSubpath()
    head.fill(nose, with: .color(rose))
    for side in [-1.0, 1.0] {
        var smile = Path(); smile.move(to: CGPoint(x: 0, y: -9))
        smile.addQuadCurve(to: CGPoint(x: side * 8, y: -5), control: CGPoint(x: side * 3, y: 0))
        stroke(smile, in: &head, width: 1.7)
    }

    // Padded headphones sit in front of the ears, with a blush-colored highlight.
    var band = Path(); band.move(to: CGPoint(x: -48, y: -24))
    band.addCurve(to: CGPoint(x: 48, y: -24), control1: CGPoint(x: -59, y: -80), control2: CGPoint(x: 59, y: -80))
    stroke(band, in: &head, width: 9)
    stroke(band, in: &head, color: Color(red: 0.56, green: 0.47, blue: 0.52), width: 3)
    for side in [-1.0, 1.0] {
        shape(roundRect(CGRect(x: side * 48 - 7, y: -36, width: 14, height: 31), radius: 6), in: &head, fill: outline)
        head.fill(roundRect(CGRect(x: side * 48 - 3, y: -31, width: 6, height: 20), radius: 3), with: .color(rose.opacity(0.70)))
    }
}

private func drawNotes(in context: inout GraphicsContext, time: Double, playing: Bool, energy: Double) {
    let positions = [CGPoint(x: 36, y: 97), CGPoint(x: 231, y: 115), CGPoint(x: 46, y: 173), CGPoint(x: 219, y: 58)]
    for (index, point) in positions.enumerated() {
        let phase = time * 1.4 + Double(index) * 1.8
        let bob = playing ? sin(phase) * (3 + energy * 3) : 0
        let symbol = playing ? (index % 2 == 0 ? "♪" : "♫") : (index % 2 == 0 ? "✦" : "·")
        context.draw(Text(symbol).font(.system(size: index % 2 == 0 ? 21 : 15, weight: .medium, design: .rounded))
            .foregroundColor((index % 2 == 0 ? rose : lavender).opacity(playing ? 0.60 : 0.35)),
                     at: CGPoint(x: point.x, y: point.y + bob))
    }
}
