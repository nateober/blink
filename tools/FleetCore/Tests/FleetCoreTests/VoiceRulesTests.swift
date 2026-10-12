import XCTest
@testable import FleetCore

final class VoiceRulesTests: XCTestCase {
  func testLevelMeterScale() {
    XCTAssertEqual(RecordingRules.level(fromPower: -160), 0)
    XCTAssertEqual(RecordingRules.level(fromPower: -60), 0)
    XCTAssertEqual(RecordingRules.level(fromPower: -30), 0.5, accuracy: 1e-9)
    XCTAssertEqual(RecordingRules.level(fromPower: 0), 1)
    XCTAssertEqual(RecordingRules.level(fromPower: 3), 1)
    XCTAssertEqual(RecordingRules.level(fromPower: .nan), 0)
  }

  func testThreeMinuteCapAndAccidentalTaps() {
    XCTAssertFalse(RecordingRules.shouldStop(elapsed: 179.9))
    XCTAssertTrue(RecordingRules.shouldStop(elapsed: 180))
    XCTAssertFalse(RecordingRules.keep(duration: 0.5))
    XCTAssertTrue(RecordingRules.keep(duration: 1.2))
    XCTAssertEqual(RecordingRules.clock(65), "1:05")
    XCTAssertEqual(RecordingRules.clock(180), "3:00")
  }

  func testHoldToTalkStopsOnRelease() {
    var m = MicInteraction()
    let t0 = Date()
    XCTAssertEqual(m.down(at: t0), .start)
    XCTAssertEqual(m.up(at: t0.addingTimeInterval(2)), .stop)
    XCTAssertEqual(m.mode, .idle)
  }

  func testTapStartsAndTheNextTapStops() {
    var m = MicInteraction()
    let t0 = Date()
    XCTAssertEqual(m.down(at: t0), .start)
    XCTAssertEqual(m.up(at: t0.addingTimeInterval(0.1)), .none)
    XCTAssertEqual(m.mode, .tapped)
    XCTAssertEqual(m.down(at: t0.addingTimeInterval(5)), .stop)
    XCTAssertEqual(m.up(at: t0.addingTimeInterval(5.1)), .none)
    XCTAssertEqual(m.mode, .idle)
  }

  func testSecondDownWhileHoldingIsIgnoredAndResetClears() {
    var m = MicInteraction()
    let t0 = Date()
    XCTAssertEqual(m.down(at: t0), .start)
    XCTAssertEqual(m.down(at: t0.addingTimeInterval(0.1)), .none)
    m.reset()
    XCTAssertEqual(m.mode, .idle)
    XCTAssertEqual(m.up(at: t0.addingTimeInterval(1)), .none)
  }

  func testVoicePathPrefersAnalyzerThenRecognizer() {
    XCTAssertEqual(VoicePath.choose(speechAuthorized: true, analyzerReady: true, recognizerOnDevice: true), .analyzer)
    XCTAssertEqual(VoicePath.choose(speechAuthorized: true, analyzerReady: false, recognizerOnDevice: true), .recognizer)
    XCTAssertEqual(VoicePath.choose(speechAuthorized: true, analyzerReady: false, recognizerOnDevice: false), .none)
    XCTAssertEqual(VoicePath.choose(speechAuthorized: false, analyzerReady: true, recognizerOnDevice: true), .none)
  }

  func testAccumulatorKeepsFinalsAndReplacesTail() {
    var a = TranscriptAccumulator()
    a.add("run the ", isFinal: false)
    XCTAssertEqual(a.text, "run the")
    a.add("run the tests", isFinal: true)
    a.add(" and", isFinal: false)
    XCTAssertEqual(a.text, "run the tests and")
    a.add(" and tell me", isFinal: false)
    XCTAssertEqual(a.text, "run the tests and tell me")
    a.add(" and tell me what broke", isFinal: true)
    XCTAssertEqual(a.text, "run the tests and tell me what broke")
  }

  func testInsertFlattensLinesAndTrims() {
    XCTAssertNil(VoiceInsert.text(from: nil))
    XCTAssertNil(VoiceInsert.text(from: "  \n "))
    XCTAssertEqual(VoiceInsert.text(from: " run the tests\nand tell me  what broke \n"),
                   "run the tests and tell me what broke")
  }

  func testInsertHexIsUTF8() {
    XCTAssertEqual(VoiceInsert.hex("ls"), "6c73")
    XCTAssertEqual(VoiceInsert.hex("don’t"), "646f6ee2809974")
  }
}
