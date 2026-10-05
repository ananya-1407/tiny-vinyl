import Foundation
import Combine

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

struct TimedLyrics: Equatable {
    let lines: [LyricLine]

    init(lrc: String) {
        let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"\[offset:([+-]?\d+)\]"#, options: .caseInsensitive)
        let fullRange = NSRange(lrc.startIndex..., in: lrc)
        var offset = 0.0
        if let match = offsetPattern.firstMatch(in: lrc, range: fullRange),
           let range = Range(match.range(at: 1), in: lrc), let value = Double(lrc[range]) {
            offset = value / 1000
        }
        var result: [LyricLine] = []
        for line in lrc.components(separatedBy: .newlines) {
            let matches = timestamp.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard let last = matches.last, let end = Range(last.range, in: line)?.upperBound else { continue }
            let text = String(line[end...]).trimmingCharacters(in: .whitespacesAndNewlines)
            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: line),
                      let secondsRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minutesRange]), let seconds = Double(line[secondsRange]), seconds < 60 else { continue }
                var fraction = 0.0
                if let range = Range(match.range(at: 3), in: line) {
                    fraction = Double("0." + line[range]) ?? 0
                }
                // Positive LRC offset means the words should appear earlier.
                result.append(LyricLine(time: max(0, minutes * 60 + seconds + fraction - offset), text: text))
            }
        }
        lines = result.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.map(\.element)
    }

    func current(at seconds: Double) -> LyricLine? {
        guard seconds.isFinite else { return nil }
        // Return one real timed line; respect empty instrumental markers and gaps.
        guard let index = lines.lastIndex(where: { $0.time <= seconds }) else { return nil }
        let line = lines[index]
        guard !line.text.isEmpty, seconds - line.time < 11 else { return nil }
        return line
    }
}

struct LyricsTrack: Hashable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Int
}

enum LyricsResult {
    case synced(TimedLyrics)
    case instrumental
    case unavailable
}

actor LyricsService {
    private struct CacheEntry {
        let result: LyricsResult
        let expiry: Date
    }
    private var cache: [LyricsTrack: CacheEntry] = [:]
    private var retryAfter = Date.distantPast

    func lyrics(for track: LyricsTrack) async throws -> LyricsResult {
        if let hit = cache[track], hit.expiry > Date() { return hit.result }
        guard Date() >= retryAfter else { return .unavailable }
        var url = URLComponents(string: "https://lrclib.net/api/get")!
        url.queryItems = [URLQueryItem(name: "track_name", value: track.title),
                          URLQueryItem(name: "artist_name", value: track.artist)]
        if !track.album.isEmpty { url.queryItems?.append(URLQueryItem(name: "album_name", value: track.album)) }
        if (1...3600).contains(track.duration) { url.queryItems?.append(URLQueryItem(name: "duration", value: String(track.duration))) }
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 15
        request.setValue("TinyVinyl/0.2.0 (https://github.com/ananya-1407/tiny-vinyl)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { return .unavailable }
        if response.statusCode == 429 {
            let raw = response.value(forHTTPHeaderField: "Retry-After") ?? "60"
            if let seconds = Double(raw) { retryAfter = Date().addingTimeInterval(max(1, seconds)) }
            else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                retryAfter = formatter.date(from: raw) ?? Date().addingTimeInterval(60)
            }
            return .unavailable
        }
        let result: LyricsResult
        if response.statusCode == 200 && data.count < 1_000_000 {
            struct Response: Decodable { let syncedLyrics: String?; let instrumental: Bool }
            let record = try JSONDecoder().decode(Response.self, from: data)
            if record.instrumental { result = .instrumental }
            else if let lrc = record.syncedLyrics {
                let parsed = TimedLyrics(lrc: lrc)
                result = parsed.lines.isEmpty ? .unavailable : .synced(parsed)
            } else { result = .unavailable }
        } else { result = .unavailable }
        if cache.count >= 100 { cache.removeAll(keepingCapacity: true) }
        cache[track] = CacheEntry(result: result, expiry: Date().addingTimeInterval(600))
        return result
    }
}

@MainActor
final class LyricsModel: ObservableObject {
    @Published private(set) var timed: TimedLyrics?
    @Published private(set) var status = "Timed lyrics appear when a match is available on LRCLIB."
    @Published var enabled = UserDefaults.standard.object(forKey: "lyricsEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "lyricsEnabled")
            let previous = track
            track = nil
            task?.cancel()
            timed = nil
            if enabled, let previous { update(previous) }
            if !enabled { status = "Lyrics are off." }
        }
    }
    private let service = LyricsService()
    private var task: Task<Void, Never>?
    private var track: LyricsTrack?

    func update(_ value: LyricsTrack?) {
        guard value != track else { return }
        task?.cancel()
        track = value
        timed = nil
        guard enabled, let value, !value.id.isEmpty, !value.id.hasPrefix("preview-"),
              !value.title.isEmpty, !value.artist.isEmpty else { return }
        status = "Finding timed lyrics on LRCLIB…"
        task = Task {
            do {
                // Avoid requests for songs the user skips past immediately.
                try await Task.sleep(nanoseconds: 400_000_000)
                let result = try await service.lyrics(for: value)
                guard !Task.isCancelled, track == value else { return }
                switch result {
                case .synced(let lyrics): timed = lyrics; status = "Timed lyrics by LRCLIB. Song title, artist, album and duration are sent for matching."
                case .instrumental: status = "Instrumental track · no lyrics."
                case .unavailable: status = "No timed lyric match for this recording."
                }
            } catch {
                guard !Task.isCancelled, track == value else { return }
                status = "Lyrics are unavailable right now."
            }
        }
    }
}
