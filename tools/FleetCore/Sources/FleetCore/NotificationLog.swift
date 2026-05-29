import Foundation

/// One received Blink push, persisted so its text survives the tap (iOS clears the
/// banner once you open the app). Decoded from the APNs payload (aps.alert + blink meta).
public struct NotificationRecord: Codable, Equatable {
  public let receivedAt: Date
  public let title: String
  public let body: String
  public let kind: String?
  public let host: String?
  public let session: String?
  public init(receivedAt: Date, title: String, body: String,
              kind: String? = nil, host: String? = nil, session: String? = nil) {
    self.receivedAt = receivedAt
    self.title = title
    self.body = body
    self.kind = kind
    self.host = host
    self.session = session
  }
}

/// Append-only (capped) log of received notifications, persisted to a plist.
/// UIKit-free so it unit-tests Mac-native; the same file compiles into BlinkConfig and
/// is fed by the AppDelegate notification handlers, read by the `notiflog` command.
public final class NotificationLog {
  private let storeURL: URL
  private let cap: Int
  private let lock = NSLock()
  private var records: [NotificationRecord]  // chronological (oldest first)

  public init(storeURL: URL, cap: Int = 200) {
    self.storeURL = storeURL
    self.cap = cap
    self.records = (try? Data(contentsOf: storeURL)).flatMap {
      try? PropertyListDecoder().decode([NotificationRecord].self, from: $0)
    } ?? []
  }

  public func append(_ record: NotificationRecord) {
    lock.lock(); defer { lock.unlock() }
    records.append(record)
    if records.count > cap { records.removeFirst(records.count - cap) }
    persist()
  }

  /// Most recent first, capped at `limit`.
  public func recent(limit: Int = 50) -> [NotificationRecord] {
    lock.lock(); defer { lock.unlock() }
    return Array(records.suffix(limit).reversed())
  }

  public func clear() {
    lock.lock(); defer { lock.unlock() }
    records.removeAll()
    persist()
  }

  private func persist() {
    if let data = try? PropertyListEncoder().encode(records) {
      try? data.write(to: storeURL, options: .atomic)
    }
  }
}
