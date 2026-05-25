import Foundation

/// APNs payload Blink sends/receives for agent-attention notifications.
/// `aps` is Apple's standard alert envelope; `blink` carries our routing metadata.
public struct BlinkPush: Codable {
  public struct Alert: Codable {
    public let title: String?
    public let body: String?
    public init(title: String? = nil, body: String? = nil) { self.title = title; self.body = body }
  }
  public struct Aps: Codable {
    public let alert: Alert?
    public let sound: String?
    public init(alert: Alert? = nil, sound: String? = nil) { self.alert = alert; self.sound = sound }
  }
  public struct Meta: Codable {
    public enum Kind: String, Codable {
      case needsInput = "needs_input"
      case done
      case progress
    }
    public let kind: Kind
    public let host: String?
    public let session: String?
    public init(kind: Kind, host: String? = nil, session: String? = nil) {
      self.kind = kind; self.host = host; self.session = session
    }
  }
  public let aps: Aps
  public let blink: Meta
  public init(aps: Aps, blink: Meta) { self.aps = aps; self.blink = blink }
}

/// Persists the device's APNs token (hex) so the fleet side can target this device.
public final class APNSTokenStore {
  private let fileURL: URL
  public init(fileURL: URL) { self.fileURL = fileURL }
  public func save(hex: String) {
    try? hex.write(to: fileURL, atomically: true, encoding: .utf8)
  }
  public func load() -> String? {
    guard let s = try? String(contentsOf: fileURL, encoding: .utf8), !s.isEmpty else { return nil }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
