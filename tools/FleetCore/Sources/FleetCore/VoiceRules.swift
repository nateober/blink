import Foundation

// Pure rules for the SmartKeys dictation key (no UIKit, no AVFoundation): the
// recording cap, the level meter, the hold-or-tap interaction, which on-device
// recognizer to use, how partial results accumulate, and what gets typed.
// Ported from the Ada app's VoiceRules.swift; tested Mac-native in FleetCoreTests.

public enum RecordingRules {
  /// A single dictation is capped here; the recording stops itself.
  public static let maxSeconds: TimeInterval = 180
  /// Shorter than this with no words heard = an accidental tap.
  public static let minSeconds: TimeInterval = 0.7

  /// Average power (dBFS) -> 0...1 for the level meter (-60 dB floor).
  public static func level(fromPower db: Float) -> Double {
    guard db.isFinite else { return 0 }
    return Double(min(1, max(0, (db + 60) / 60)))
  }

  public static func shouldStop(elapsed: TimeInterval) -> Bool { elapsed >= maxSeconds }
  public static func keep(duration: TimeInterval) -> Bool { duration >= minSeconds }

  public static func clock(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.down))
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}

/// Press-and-hold (>= 0.35 s) records until release; a quick tap starts recording and the
/// next tap stops it.
public struct MicInteraction {
  public enum Mode: Equatable { case idle, holding, tapped }
  public enum Effect: Equatable { case start, stop, none }
  public static let holdThreshold: TimeInterval = 0.35

  public private(set) var mode: Mode = .idle
  private var downAt: Date?

  public init() {}

  public mutating func down(at t: Date) -> Effect {
    switch mode {
    case .idle:
      mode = .holding
      downAt = t
      return .start
    case .tapped:
      mode = .idle
      downAt = nil
      return .stop
    case .holding:
      return .none
    }
  }

  public mutating func up(at t: Date) -> Effect {
    guard mode == .holding, let d = downAt else { return .none }
    downAt = nil
    if t.timeIntervalSince(d) >= Self.holdThreshold {
      mode = .idle
      return .stop
    }
    mode = .tapped
    return .none
  }

  public mutating func reset() {
    mode = .idle
    downAt = nil
  }
}

/// Which recognizer a recording uses. Blink is text-only: with no on-device path the mic
/// stays shut and the strip says why (there is no upload fallback here).
public enum VoicePath: Equatable {
  case analyzer       // iOS 26 SpeechAnalyzer + SpeechTranscriber
  case recognizer     // SFSpeechRecognizer, requiresOnDeviceRecognition
  case none           // Speech denied, or no on-device model

  public static func choose(speechAuthorized: Bool, analyzerReady: Bool,
                            recognizerOnDevice: Bool) -> VoicePath {
    guard speechAuthorized else { return .none }
    if analyzerReady { return .analyzer }
    return recognizerOnDevice ? .recognizer : .none
  }
}

/// SpeechTranscriber reports finalized segments plus a volatile tail that each update
/// replaces; the live text is all finals + the latest tail.
public struct TranscriptAccumulator {
  private var finals = ""
  private var tail = ""

  public init() {}

  public var text: String { (finals + tail).trimmingCharacters(in: .whitespacesAndNewlines) }

  public mutating func add(_ segment: String, isFinal: Bool) {
    if isFinal {
      finals += segment
      tail = ""
    } else {
      tail = segment
    }
  }
}

/// What a finished dictation types into the terminal.
public enum VoiceInsert {
  /// The words, trimmed, with line breaks flattened to spaces (a terminal line is one
  /// line; Return is the user's). Nil when there is nothing worth typing.
  public static func text(from transcript: String?) -> String? {
    guard let transcript else { return nil }
    let flat = transcript
      .replacingOccurrences(of: "[\\r\\n]+", with: " ", options: .regularExpression)
      .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return flat.isEmpty ? nil : flat
  }

  /// UTF-8 bytes as lowercase hex, the raw-input path SmartKeys use (`reportHex`).
  public static func hex(_ s: String) -> String {
    s.utf8.map { String(format: "%02x", $0) }.joined()
  }
}
