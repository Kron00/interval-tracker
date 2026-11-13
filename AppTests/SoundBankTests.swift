import AVFoundation
import IntervalCore
import XCTest
@testable import IntervalTracker

@MainActor
final class SoundBankTests: XCTestCase {
    func testTonesFillTheirSlots() throws {
        let bank = SoundBank(log: AudioLog())
        for sound in [Sound.tick, .phaseChange, .finish] {
            let buffer = try XCTUnwrap(bank[sound], "\(sound) has no buffer")
            XCTAssertEqual(seconds(of: buffer), sound.slot, accuracy: 0.01, "\(sound)")
            XCTAssertGreaterThan(peak(of: buffer), 0.3, "\(sound) is silent")
        }
    }

    func testTheRepBeatIsSofterThanTheCountdownTick() throws {
        let bank = SoundBank(log: AudioLog())
        let beat = try XCTUnwrap(bank[.beat])
        let tick = try XCTUnwrap(bank[.tick])
        XCTAssertEqual(seconds(of: beat), Sound.beat.slot, accuracy: 0.01)
        XCTAssertGreaterThan(peak(of: beat), 0.1, "the beat is silent")
        XCTAssertLessThan(peak(of: beat), peak(of: tick) * 0.6)
    }

    func testVoicePhrasesRenderWithinTheirSlots() async throws {
        let phrases = try await rendered(.norwegian4x4)
        XCTAssertEqual(phrases.count, 8, "warm-up, rounds one to three, last round, rest, cool-down, complete")
        for phrase in phrases {
            XCTAssertLessThanOrEqual(seconds(of: phrase.buffer), phrase.sound.slot + 0.001, "\(phrase.sound)")
            XCTAssertGreaterThan(seconds(of: phrase.buffer), 0.15, "\(phrase.sound)")
        }
    }

    /// A stretch name is free text, and the schedule gives it a slot worked out from its length alone.
    /// A buffer that fills its slot to the last sample was cut, so part of the name would go unheard.
    func testEveryDailyStretchNameIsSpokenInFull() async throws {
        let phrases = try await rendered(.dailyStretch)
        XCTAssertEqual(phrases.count, 12, "ten stretch names, switch sides, complete")
        XCTAssertEqual(phrases.first?.sound, .voice(Utterance("Cat-Cow")), "the first name a run needs is rendered first")
        for phrase in phrases {
            let slot = Int(phrase.sound.slot * phrase.buffer.format.sampleRate)
            XCTAssertLessThan(Int(phrase.buffer.frameLength), slot, "\(phrase.sound) ran to \(phrase.sound.slot) s and was cut")
            XCTAssertGreaterThan(seconds(of: phrase.buffer), 0.15, "\(phrase.sound)")
        }
    }

    private func rendered(_ workout: Workout) async throws -> [(sound: Sound, buffer: AVAudioPCMBuffer)] {
        guard AVSpeechSynthesisVoice(language: "en-US") != nil else {
            throw XCTSkip("This simulator has no en-US speech voice.")
        }
        let log = AudioLog()
        let bank = SoundBank(log: log)
        let schedule = try XCTUnwrap(Session(workout, cues: CuePreferences(), startingAt: .now).cueSchedule)
        let voices = schedule.vocabulary.filter { if case .voice = $0 { true } else { false } }

        // The simulator's speech service can time out for a minute after boot, most often on CI. The bank
        // renders a failed phrase again on a later call, as the app does when a run starts or skips.
        let started = Date.now
        var phrases: [(sound: Sound, buffer: AVAudioPCMBuffer)] = []
        for _ in 0..<4 where phrases.count < voices.count {
            await bank.prepare(schedule.vocabulary)
            phrases = voices.compactMap { sound in bank[sound].map { (sound: sound, buffer: $0) } }
        }
        let elapsed = Date.now.timeIntervalSince(started)

        if phrases.count < voices.count {
            throw XCTSkip("The speech service rendered \(phrases.count) of \(voices.count) phrases in this simulator, so the slots cannot be checked here: \(log.lines)")
        }
        print("voice render: \(workout.name), \(phrases.count) phrases in \(elapsed) s, lengths \(phrases.map { "\($0.sound): \(seconds(of: $0.buffer)) of \($0.sound.slot)" }), log: \(log.lines)")
        return phrases
    }

    private func seconds(of buffer: AVAudioPCMBuffer) -> Double {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }

    private func peak(of buffer: AVAudioPCMBuffer) -> Float {
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        return samples.map(abs).max() ?? 0
    }
}
