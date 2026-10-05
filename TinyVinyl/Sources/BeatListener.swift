import Cocoa
import CoreAudio
import Combine

/// Captures Spotify's output only. Never taps the microphone, never saves or uploads audio.
@MainActor
final class BeatListener: ObservableObject {
    @Published private(set) var frame = RhythmFrame()
    @Published private(set) var active = false
    @Published private(set) var receivingAudio = false
    @Published private(set) var status = "Beat sync is ready when Spotify plays."
    @Published var enabled = UserDefaults.standard.object(forKey: "beatSyncEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "beatSyncEnabled")
            if !enabled { stop(); status = "Gentle animation · beat sync is off." }
            else { failed = false; nextCheck = .distantPast }
        }
    }
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var callback: AudioDeviceIOProcID?
    private var processes: [AudioObjectID] = []
    private var failed = false
    private var nextCheck = Date.distantPast
    private var generation = 0
    private let queue = DispatchQueue(label: "local.tinyvinyl.beats", qos: .userInitiated)

    func update(playing: Bool, preview: Bool) {
        guard enabled, !preview, playing else {
            if active { stop() }
            return
        }
        guard !failed, Date() >= nextCheck else { return }
        nextCheck = Date().addingTimeInterval(5)
        guard #available(macOS 14.2, *) else {
            status = "Live beat sync needs macOS 14.2 or later. Gentle animation is available."
            return
        }
        let ids = Self.spotifyProcesses()
        guard !ids.isEmpty else {
            status = "Waiting for Spotify’s audio."
            if active { stop() }
            return
        }
        if active && ids == processes { return }
        stop()
        do {
            try start(processes: ids)
            processes = ids
            active = true
            status = "Waiting for Spotify audio. Allow the macOS audio prompt if shown."
        } catch {
            stop()
            failed = true
            status = "Beat sync needs audio access. Allow Tiny Vinyl in System Settings → Privacy & Security → Screen & System Audio Recording, then retry."
            NSLog("Tiny Vinyl beat sync: %@", error.localizedDescription)
        }
    }

    func retry() {
        stop()
        failed = false
        enabled = true
        nextCheck = .distantPast
    }

    func stop() {
        generation += 1
        if let callback, device != 0 {
            AudioDeviceStop(device, callback)
            AudioDeviceDestroyIOProcID(device, callback)
        }
        callback = nil
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if #available(macOS 14.2, *), tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
        active = false
        receivingAudio = false
        processes = []
        frame = RhythmFrame()
    }

    @available(macOS 14.2, *)
    private func start(processes: [AudioObjectID]) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.name = "Tiny Vinyl · Spotify rhythm"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap))
        var format = AudioStreamBasicDescription()
        var address = Self.address(kAudioTapPropertyFormat)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format))
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw NSError(domain: "TinyVinyl.Audio", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported audio sample format."])
        }
        let configuration: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tiny Vinyl · Private beat listener",
            kAudioAggregateDeviceUIDKey: "local.tinyvinyl.beats.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &device))
        let currentGeneration = generation
        let meter = AudioMeter()
        try check(AudioDeviceCreateIOProcIDWithBlock(&callback, device, queue) { [weak self] _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            var sum = 0.0
            var count = 0
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                let length = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                for index in 0..<length {
                    let sample = Double(samples[index])
                    if sample.isFinite { sum += sample * sample; count += 1 }
                }
            }
            guard count > 0 else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let value = meter.analyzer.consume(rms: sqrt(sum / Double(count)), time: now)
            if now - meter.lastPublish >= 1.0 / 30.0 {
                meter.lastPublish = now
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    if !self.receivingAudio {
                        self.receivingAudio = true
                        self.status = "Live beat sync · Spotify audio only · processed on this Mac."
                    }
                    self.frame = value
                }
            }
        })
        try check(AudioDeviceStart(device, callback))
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    @available(macOS 14.2, *)
    private static func spotifyProcesses() -> [AudioObjectID] {
        var property = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !values.isEmpty else { return [] }
        let result = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return [] }
        return values.filter { process in
            var bundleProperty = address(kAudioProcessPropertyBundleID)
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundle: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(process, &bundleProperty, 0, nil, &bundleSize, &bundle) == noErr,
                  let bundle else { return false }
            let identifier = bundle.takeRetainedValue() as String
            return identifier == "com.spotify.client" || identifier.hasPrefix("com.spotify.client.")
        }.sorted()
    }
}

/// Used exclusively on the audio dispatch queue.
private final class AudioMeter {
    var analyzer = RhythmAnalysis()
    var lastPublish = 0.0
}
