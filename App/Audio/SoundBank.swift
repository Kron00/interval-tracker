import AVFoundation
import IntervalCore

@MainActor
final class SoundBank {
    let format: AVAudioFormat
    let silence: AVAudioPCMBuffer

    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var rendering: Set<Sound> = []
    private let log: AudioLog

    private static let sampleRate = 44_100.0
    private static let tones: [Sound: (pitches: [Double], gain: Double)] = [
        .tick: ([880], 0.6),
        .phaseChange: ([1320], 0.6),
        .finish: ([1320, 1760], 0.6),
    ]
    /// The most the speech rate may be raised to fit a phrase into its slot. Speech gets about three
    /// times as much faster as the rate rises, so 1.2 is 1.6 times normal speed. Past that it is hard to follow.
    private static let fastestSpeechRate = 1.2

    init(log: AudioLog) {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        self.format = format
        self.log = log
        silence = Self.buffer([Float](repeating: 0, count: Int(Self.sampleRate)), format)
        for (sound, tone) in Self.tones {
            let each = sound.slot / Double(tone.pitches.count)
            buffers[sound] = Self.buffer(tone.pitches.flatMap { Self.sine($0, seconds: each, gain: tone.gain) }, format)
        }
    }

    subscript(sound: Sound) -> AVAudioPCMBuffer? { buffers[sound] }

    /// Renders the voice phrases in `sounds` that have no buffer yet, in the order given, so the phrase
    /// a run needs first is ready first. Returns true when it added one.
    /// A phrase that fails twice is left without a buffer, so the next call tries it again.
    @discardableResult
    func prepare(_ sounds: [Sound]) async -> Bool {
        var added = false
        for sound in sounds {
            guard case .voice(let utterance) = sound, buffers[sound] == nil, rendering.insert(sound).inserted else { continue }
            defer { rendering.remove(sound) }
            for attempt in 1...2 {
                if let buffer = await voiceBuffer(utterance) {
                    buffers[sound] = buffer
                    added = true
                    break
                }
                log.note("voice \"\(utterance.text)\" did not render, attempt \(attempt) of 2")
            }
        }
        return added
    }

    /// The schedule reserves `utterance.slot` and no more, so a phrase that runs long is spoken again
    /// faster, and cut only if it still does not fit.
    private func voiceBuffer(_ utterance: Utterance) async -> AVAudioPCMBuffer? {
        let limit = Int(utterance.slot * Self.sampleRate)
        var samples = Self.withoutSilence(await SpeechRender(target: format).samples(for: utterance.text, rate: 1))
        if samples.count > limit {
            let speedNeeded = 1.1 * Double(samples.count) / Double(limit)
            let rate = min(Self.fastestSpeechRate, 1 + (speedNeeded - 1) / 3)
            let faster = Self.withoutSilence(await SpeechRender(target: format).samples(for: utterance.text, rate: rate))
            if !faster.isEmpty { samples = faster }
            if samples.count > limit {
                log.note("voice \"\(utterance.text)\" is cut to its \(utterance.slot) s slot")
            }
        }
        return Self.phraseBuffer(samples, limit: limit, format)
    }

    private static func sine(_ hertz: Double, seconds: TimeInterval, gain: Double) -> [Float] {
        let count = Int(seconds * sampleRate)
        let ramp = 0.005 * sampleRate
        return (0..<count).map { index in
            let envelope = min(1, Double(min(index, count - 1 - index)) / ramp)
            return Float(gain * envelope * sin(2 * .pi * hertz * Double(index) / sampleRate))
        }
    }

    private static func withoutSilence(_ rendered: [Float]) -> [Float] {
        guard let first = rendered.firstIndex(where: { abs($0) >= 0.01 }),
              let last = rendered.lastIndex(where: { abs($0) >= 0.01 }) else { return [] }
        return Array(rendered[first...last])
    }

    private static func phraseBuffer(_ speech: [Float], limit: Int, _ format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var samples = speech
        guard let peak = samples.map(abs).max() else { return nil }
        let gain = 0.9 / peak
        for index in samples.indices { samples[index] *= gain }

        if samples.count > limit {
            samples.removeLast(samples.count - limit)
            let fade = Int(0.020 * sampleRate)
            for step in 0..<fade {
                samples[limit - fade + step] *= Float(fade - step) / Float(fade)
            }
        }
        return buffer(samples, format)
    }

    private static func buffer(_ samples: [Float], _ format: AVAudioFormat) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(samples.count)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}

private final class SpeechRender: @unchecked Sendable {
    private let target: AVAudioFormat
    private var synthesizer: AVSpeechSynthesizer?
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var continuation: CheckedContinuation<[Float], Never>?

    private static let timeout: TimeInterval = 5
    private static let queue = DispatchQueue(label: "IntervalTracker.speech", qos: .userInitiated)

    init(target: AVAudioFormat) { self.target = target }

    func samples(for text: String, rate: Double) async -> [Float] {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            // Looking up a voice waits on the system speech service, for minutes on a cold simulator.
            // On the main thread that froze the whole app, so every speech call runs on this queue.
            Self.queue.async { [self] in
                let synthesizer = AVSpeechSynthesizer()
                lock.withLock { self.synthesizer = synthesizer }
                let utterance = AVSpeechUtterance(string: text)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
                synthesizer.write(utterance) { [self] buffer in
                    guard let chunk = buffer as? AVAudioPCMBuffer else { return }
                    if chunk.frameLength == 0 { finish() } else { append(chunk) }
                }
                Self.queue.asyncAfter(deadline: .now() + Self.timeout) { [self] in finish() }
            }
        }
    }

    private func append(_ chunk: AVAudioPCMBuffer) {
        lock.withLock {
            if converter?.inputFormat != chunk.format {
                converter = AVAudioConverter(from: chunk.format, to: target)
            }
            let capacity = AVAudioFrameCount(Double(chunk.frameLength) * target.sampleRate / chunk.format.sampleRate) + 1024
            guard let converter, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }

            var supplied = false
            var failure: NSError?
            let status = converter.convert(to: output, error: &failure) { _, inputStatus in
                if supplied {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                inputStatus.pointee = .haveData
                return chunk
            }
            guard status != .error, let channel = output.floatChannelData else { return }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(output.frameLength)))
        }
    }

    private func finish() {
        let (waiting, rendered) = lock.withLock { () -> (CheckedContinuation<[Float], Never>?, [Float]) in
            defer { continuation = nil }
            return (continuation, samples)
        }
        waiting?.resume(returning: rendered)
    }
}
