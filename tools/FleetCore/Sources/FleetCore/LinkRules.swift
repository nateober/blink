import Foundation

// Pure rules for "open a link on screen": which of the links found in the terminal
// are offered, in what order, and how each is shown in the list.
public enum LinkPicker {
  public static let maxChoices = 8
  static let schemes: Set<String> = ["http", "https", "mailto", "ssh"]

  /// `links` come top to bottom as found on screen. The newest output is at the bottom, so
  /// the result is bottom first, without repeats, limited to links Blink should open.
  public static func choices(from links: [String]) -> [URL] {
    var seen = Set<String>()
    var out: [URL] = []
    for link in links.reversed() {
      guard out.count < maxChoices,
            let url = URL(string: link),
            let scheme = url.scheme?.lowercased(), schemes.contains(scheme),
            seen.insert(url.absoluteString).inserted
      else { continue }
      out.append(url)
    }
    return out
  }

  /// A one-line label: no scheme for web links, middle cut when long.
  public static func label(for url: URL, limit: Int = 56) -> String {
    var text = url.absoluteString
    for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
      text.removeFirst(prefix.count)
    }
    if text.hasSuffix("/") { text.removeLast() }
    guard text.count > limit, limit > 8 else { return text }
    let head = (limit - 1) * 2 / 3, tail = limit - 1 - head
    return String(text.prefix(head)) + "…" + String(text.suffix(tail))
  }
}
