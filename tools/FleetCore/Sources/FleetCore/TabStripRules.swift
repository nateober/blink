import Foundation

// Pure rules for the optional sessions bar: what each tab says and when the bar shows.
public enum TabStripRules {
  public static let height: Double = 28
  public static let maxLabelLength = 28

  /// A tab's label from the terminal's title. An untitled session is "blink" like the HUD.
  public static func label(title: String?, index: Int) -> String {
    var text = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    // Leading status marks some programs put in the title (spinners, bullets) add nothing here.
    while let first = text.unicodeScalars.first,
          !CharacterSet.alphanumerics.contains(first), text.count > 1,
          !"~/.[(".unicodeScalars.contains(first) {
      text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
    if text.isEmpty { text = "blink" }
    if text.count > maxLabelLength {
      text = String(text.prefix(maxLabelLength - 1)) + "…"
    }
    return "\(index + 1)  \(text)"
  }

  /// One session needs no bar, and the Snips input covers the same space.
  public static func isVisible(enabled: Bool, sessions: Int, snipsInputActive: Bool) -> Bool {
    enabled && sessions > 1 && !snipsInputActive
  }

  /// The y below which the terminal has to start so the bar doesn't cover its first rows.
  public static func reservedTop(visible: Bool, safeAreaTop: Double) -> Double {
    visible ? safeAreaTop + height : 0
  }
}
