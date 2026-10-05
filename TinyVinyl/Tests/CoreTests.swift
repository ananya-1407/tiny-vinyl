import Foundation

@main
struct CoreTests {
    static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ description: String) {
            precondition(value(), description)
            checks += 1
        }

        // All fixture text is original, not song lyrics.
        let lyrics = TimedLyrics(lrc: """
        [ar:Example]
        [offset:100]
        [00:01.20]A tiny cat says hello
        [00:04.345][00:08.0]Paws in the air ♡
        [00:06.00]
        [00:99.10]invalid timestamp
        [00:12]अच्छा दिन
        """)
        check(lyrics.lines.count == 5, "Metadata and invalid timestamps must be ignored; repeated timestamps retained")
        check(abs(lyrics.lines[0].time - 1.1) < 0.0001, "LRC fractions and positive offsets must be applied")
        check(lyrics.current(at: 0.5) == nil, "Do not display words before their time")
        check(lyrics.current(at: 4.8)?.text == "Paws in the air ♡", "Find current line")
        check(lyrics.current(at: 6.5) == nil, "Blank timestamps must clear the bubble")
        check(lyrics.current(at: 8.2)?.text == "Paws in the air ♡", "Repeated line timings must work")
        check(lyrics.current(at: 2)?.text == "A tiny cat says hello", "Seeking backward must select an earlier line")
        check(lyrics.current(at: 12)?.text == "अच्छा दिन", "Preserve non-Latin lyrics")
        check(lyrics.current(at: 30) == nil, "Do not leave stale words floating through a long instrumental")
        check(lyrics.current(at: .nan) == nil, "Invalid playback times must not crash")
        let delayed = TimedLyrics(lrc: "[offset:-500]\n[00:01]hello")
        check(delayed.lines.first?.time == 1.5, "Negative offsets must delay lyrics")
        let sorted = TimedLyrics(lrc: "[00:10]later\n[00:02]earlier")
        check(sorted.current(at: 3)?.text == "earlier", "Sort out-of-order lines")

        var silence = RhythmAnalysis()
        for i in 0..<100 { _ = silence.consume(rms: 0, time: Double(i) * 0.01) }
        check(silence.frame.energy == 0 && silence.frame.pulse == 0, "Silence must not fabricate beats")
        var rhythm = RhythmAnalysis()
        var detected = 0
        for i in 0..<800 {
            let rms = i % 50 < 3 ? 0.25 : 0.008
            let previous = rhythm.frame.pulse
            let value = rhythm.consume(rms: rms, time: Double(i) * 0.01)
            if value.pulse == 1 && previous < 1 { detected += 1 }
            check((0...1).contains(value.energy) && (0...1).contains(value.pulse), "Animation inputs must remain bounded")
        }
        check(detected >= 12, "Regular audio transients should trigger dancing")
        check(abs(rhythm.frame.tempo - 120) < 1, "Estimate tempo from repeated onsets")
        for i in 800..<1100 { _ = rhythm.consume(rms: 0, time: Double(i) * 0.01) }
        check(rhythm.frame.energy < 0.01 && rhythm.frame.pulse < 0.01, "Settle down when audio becomes quiet")
        let before = rhythm.frame.energy
        _ = rhythm.consume(rms: .nan, time: 11)
        check(rhythm.frame.energy == before, "Ignore malformed audio samples")
        print("Passed \(checks) lyric timing and rhythm checks.")

        if CommandLine.arguments.contains("--live-lyrics") {
            let service = LyricsService()
            let track = LyricsTrack(id: "integration-test", title: "Maahi Ve", artist: "A.R. Rahman", album: "Highway", duration: 240)
            let result = try await service.lyrics(for: track)
            if case .synced(let timed) = result {
                print("Live LRCLIB response: \(timed.lines.count) timed entries parsed. No lyric text logged.")
            } else { print("Live LRCLIB response: no timed match for the test recording.") }
        }
    }
}
