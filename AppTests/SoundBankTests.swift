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

    func testVoicePhrasesRenderWithinTheirSlots() async throws {
        guard AVSpeechSynthesisVoice(language: "en-US") != nil else {
            throw XCTSkip("This simulator has no en-US speech voice.")
        }
        let log = AudioLog()
        let bank = SoundBank(log: log)
        let schedule = try XCTUnwrap(
            Session(.norwegian4x4, cues: CuePreferences(), startingAt: .now).cueSchedule)
        let phrases = schedule.vocabulary.filter { if case .voice = $0 { true } else { false } }
        XCTAssertEqual(phrases.count, 8, "warm-up, rounds one to three, last round, rest, cool-down, complete")

        let started = Date.now
        await bank.prepare(schedule.vocabulary)
        let elapsed = Date.now.timeIntervalSince(started)

        let rendered = phrases.filter { bank[$0] != nil }
        if rendered.isEmpty {
            throw XCTSkip("Speech synthesis produced no audio in this simulator: \(log.lines)")
        }
        XCTAssertEqual(rendered.count, phrases.count, log.lines.joined(separator: "\n"))
        for phrase in rendered {
            let buffer = try XCTUnwrap(bank[phrase])
            XCTAssertLessThanOrEqual(seconds(of: buffer), phrase.slot + 0.001, "\(phrase)")
            XCTAssertGreaterThan(seconds(of: buffer), 0.15, "\(phrase)")
        }
        XCTAssertLessThan(elapsed, 30, "Rendering 8 phrases took \(elapsed) s, so most renders are hitting the timeout.")
        print("voice render: \(rendered.count) phrases in \(elapsed) s, log: \(log.lines)")
    }

    private func seconds(of buffer: AVAudioPCMBuffer) -> Double {
        Double(buffer.frameLength) / buffer.format.sampleRate
    }

    private func peak(of buffer: AVAudioPCMBuffer) -> Float {
        let samples = UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        return samples.map(abs).max() ?? 0
    }
}
