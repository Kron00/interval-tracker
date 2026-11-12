import AVFoundation
import IntervalCore

/// Every buffer is in `format` and no longer than its sound's `slot`.
@MainActor
final class SoundBank {
    let format: AVAudioFormat
    let silence: AVAudioPCMBuffer

    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var attempted: Set<Sound> = []
    private let log: AudioLog

    private static let sampleRate = 44_100.0
    private static let tones: [Sound: [Double]] = [
        .tick: [880],
        .phaseChange: [1320],
        .finish: [1320, 1760],
    ]

    init(log: AudioLog) {
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
        self.format = format
        self.log = log
        silence = Self.buffer([Float](repeating: 0, count: Int(Self.sampleRate)), format)
        for (sound, pitches) in Self.tones {
            let each = sound.slot / Double(pitches.count)
            buffers[sound] = Self.buffer(pitches.flatMap { Self.sine($0, seconds: each) }, format)
        }
    }

    /// nil only for a voice phrase that has not been rendered, or failed to render.
    subscript(sound: Sound) -> AVAudioPCMBuffer? { buffers[sound] }

    /// Renders the voice phrases in `sounds` that were never attempted. Returns true when it added a buffer.
    @discardableResult
    func prepare(_ sounds: Set<Sound>) async -> Bool {
        var added = false
        for sound in sounds {
            guard case .voice(let phrase) = sound, attempted.insert(sound).inserted else { continue }
            let samples = await SpeechRender(target: format).samples(for: phrase.spokenText)
            if let buffer = Self.phraseBuffer(samples, slot: sound.slot, format) {
                buffers[sound] = buffer
                added = true
            } else {
                log.note("voice \"\(phrase.spokenText)\" did not render, cue skipped")
            }
        }
        return added
    }

    private static func sine(_ hertz: Double, seconds: TimeInterval) -> [Float] {
        let count = Int(seconds * sampleRate)
        let ramp = 0.005 * sampleRate
        return (0..<count).map { index in
            let envelope = min(1, Double(min(index, count - 1 - index)) / ramp)
            return Float(0.6 * envelope * sin(2 * .pi * hertz * Double(index) / sampleRate))
        }
    }

    private static func phraseBuffer(_ rendered: [Float], slot: TimeInterval, _ format: AVAudioFormat) -> AVAudioPCMBuffer? {
        var samples = Array(rendered.drop { abs($0) < 0.01 })
        guard let peak = samples.map(abs).max() else { return nil }
        let gain = 0.9 / peak
        for index in samples.indices { samples[index] *= gain }

        let limit = Int(slot * sampleRate)
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

/// One utterance rendered to mono samples in `target`. The synthesizer calls back off the main thread,
/// so everything it touches sits behind the lock.
private final class SpeechRender: @unchecked Sendable {
    private let target: AVAudioFormat
    private let synthesizer = AVSpeechSynthesizer()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var continuation: CheckedContinuation<[Float], Never>?

    private static let timeout: TimeInterval = 5

    init(target: AVAudioFormat) { self.target = target }

    /// Empty when the synthesizer produced nothing before the timeout.
    func samples(for text: String) async -> [Float] {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            synthesizer.write(utterance) { [self] buffer in
                guard let chunk = buffer as? AVAudioPCMBuffer else { return }
                if chunk.frameLength == 0 { finish() } else { append(chunk) }
            }
            // This closure also keeps the synthesizer alive until the render is over.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [self] in finish() }
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
