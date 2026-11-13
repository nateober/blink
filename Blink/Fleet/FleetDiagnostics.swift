//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork
//
// FleetDiagnostics: keeps the reports iOS makes about this app (MetricKit: why it was
// ended, crashes, hangs) and hands them to a fleet host over SSH, so "the app got killed
// again" can be answered from `~/Scratch/blink-diag/` there instead of from the phone's
// Settings. Names, limits and the upload commands are in FleetCore (DiagUpload).
//
// Blink is free software under the GNU GPL v3; see <http://www.github.com/blinksh/blink>.
//
//////////////////////////////////////////////////////////////////////////////////

import Foundation
import MetricKit
import UIKit

@objc final class FleetDiagnostics: NSObject, MXMetricManagerSubscriber {
  @objc static let shared = FleetDiagnostics()

  private let queue = DispatchQueue(label: "blink.fleet.diagnostics")
  private var sending = false
  private var serial = 0
  private var lastAttempt = Date.distantPast
  private static let pastTakenKey = "FleetDiagnosticsPastTaken"
  /// A host that doesn't answer is not asked again for this long.
  private static let retryAfter: TimeInterval = 15 * 60
  private static let perPass = 8

  private var directory: URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      return nil
    }
    let dir = base.appendingPathComponent("FleetDiagnostics", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @objc func start() {
    MXMetricManager.shared.add(self)
    if !UserDefaults.standard.bool(forKey: Self.pastTakenKey) {
      // Whatever iOS still holds from before this build subscribed. Off the main thread:
      // this runs during launch.
      UserDefaults.standard.set(true, forKey: Self.pastTakenKey)
      DispatchQueue.global(qos: .utility).async {
        self.store(MXMetricManager.shared.pastPayloads.map { $0.jsonRepresentation() }, kind: .metrics)
        self.store(MXMetricManager.shared.pastDiagnosticPayloads.map { $0.jsonRepresentation() }, kind: .diagnostics)
        self.sendPending()
      }
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil
    ) { [weak self] _ in
      self?.sendPending()
    }
  }

  func didReceive(_ payloads: [MXMetricPayload]) {
    store(payloads.map { $0.jsonRepresentation() }, kind: .metrics)
    sendPending()
  }

  func didReceive(_ payloads: [MXDiagnosticPayload]) {
    store(payloads.map { $0.jsonRepresentation() }, kind: .diagnostics)
    sendPending()
  }

  private func store(_ reports: [Data], kind: DiagUpload.Kind) {
    guard !reports.isEmpty else { return }
    queue.async {
      guard let dir = self.directory else { return }
      for report in reports {
        self.serial += 1
        let name = DiagUpload.fileName(kind: kind, at: Date(), serial: self.serial)
        try? report.write(to: dir.appendingPathComponent(name), options: .atomic)
      }
      let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
      for name in DiagUpload.overflow(names) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
      }
    }
  }

  /// Sends what is waiting to the first fleet host that takes it. A host is one that
  /// answered the session switcher, so nothing goes to a host entry outside the fleet.
  func sendPending() {
    queue.async {
      guard !self.sending, Date().timeIntervalSince(self.lastAttempt) > Self.retryAfter,
            let dir = self.directory else { return }
      let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        .filter(DiagUpload.isReportName).sorted()
      let hosts = AgentSettings.sessionHosts
      guard !names.isEmpty, !hosts.isEmpty else { return }
      self.sending = true
      self.lastAttempt = Date()
      let batch = Array(names.prefix(Self.perPass))
      Task.detached(priority: .utility) {
        var sentAll = false
        for alias in hosts {
          var sent = 0
          for name in batch {
            let file = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file) else { continue }
            guard await Self.upload(data, name: name, alias: alias) else { break }
            try? FileManager.default.removeItem(at: file)
            sent += 1
          }
          if sent > 0 {
            sentAll = sent == batch.count
            break
          }
        }
        let more = sentAll && names.count > batch.count
        self.queue.async {
          self.sending = false
          if more {
            self.lastAttempt = .distantPast
            self.sendPending()
          }
        }
      }
    }
  }

  private static func upload(_ data: Data, name: String, alias: String) async -> Bool {
    let commands = DiagUpload.commands(base64: data.base64EncodedString(), fileName: name)
    guard !commands.isEmpty else { return false }
    var last = ""
    for command in commands {
      guard let result = try? await HeadlessSSHRunner.run(alias: alias, command: command, overallTimeout: 30),
            result.exitOK else { return false }
      last = result.stdout
    }
    return DiagUpload.confirmed(stdout: last, fileName: name)
  }
}
