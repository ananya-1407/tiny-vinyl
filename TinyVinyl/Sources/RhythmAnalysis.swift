import Foundation

struct RhythmFrame {
    var energy = 0.0
    var pulse = 0.0
    var tempo = 100.0
}

/// Lightweight onset detection, not a song/genre classifier. No audio is retained.
struct RhythmAnalysis {
    private var baseline = 0.025
    private var lastBeat = -10.0
    private var previousTime = 0.0
    private var intervals: [Double] = []
    private(set) var frame = RhythmFrame()

    mutating func consume(rms: Double, time: Double) -> RhythmFrame {
        guard rms.isFinite, time.isFinite else { return frame }
        let dt = max(0.001, min(0.1, time - previousTime))
        previousTime = time
        let level = max(0, min(1, rms))
        let threshold = max(0.012, baseline * 1.45)
        if level > threshold && time - lastBeat > 0.26 {
            let interval = time - lastBeat
            if (0.30...1.10).contains(interval) {
                intervals.append(interval)
                if intervals.count > 7 { intervals.removeFirst() }
                let sorted = intervals.sorted()
                frame.tempo = max(60, min(180, 60 / sorted[sorted.count / 2]))
            }
            lastBeat = time
            frame.pulse = 1
        } else {
            frame.pulse *= exp(-dt * 9)
        }
        baseline += (level - baseline) * (1 - exp(-dt * 2.8))
        let target = pow(min(1, level * 6), 0.65)
        frame.energy += (target - frame.energy) * (1 - exp(-dt * (target > frame.energy ? 16 : 5)))
        return frame
    }
}
