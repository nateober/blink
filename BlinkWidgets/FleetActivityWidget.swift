//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork  ·  WIDGET EXTENSION
//
// The Live Activity UI: lock-screen / banner view + Dynamic Island. Lives in the widget
// extension target. Requires FleetActivityAttributes.swift to ALSO be a member of this
// target (add the existing file — don't duplicate it). See docs/LIVE-ACTIVITY-SETUP.md.
//
//////////////////////////////////////////////////////////////////////////////////

import SwiftUI
import WidgetKit
import ActivityKit

@available(iOS 16.1, *)
struct FleetActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: FleetActivityAttributes.self) { context in
      // Lock screen / banner.
      HStack(spacing: 12) {
        Image(systemName: icon(context.state.status))
          .font(.title2)
          .foregroundStyle(tint(context.state.status))
        VStack(alignment: .leading, spacing: 2) {
          Text("\(context.attributes.sessionLabel) · \(context.attributes.host)")
            .font(.headline)
          Text(context.state.detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Spacer()
        Text(context.state.status)
          .font(.caption.weight(.semibold))
          .foregroundStyle(tint(context.state.status))
      }
      .padding()
      .activityBackgroundTint(Color.black.opacity(0.25))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: icon(context.state.status)).foregroundStyle(tint(context.state.status))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.status).font(.caption.weight(.semibold)).foregroundStyle(tint(context.state.status))
        }
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 1) {
            Text("\(context.attributes.sessionLabel) · \(context.attributes.host)").font(.caption.weight(.semibold))
            Text(context.state.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          }
        }
      } compactLeading: {
        Image(systemName: icon(context.state.status)).foregroundStyle(tint(context.state.status))
      } compactTrailing: {
        Text(short(context.state.status)).font(.caption2)
      } minimal: {
        Image(systemName: icon(context.state.status)).foregroundStyle(tint(context.state.status))
      }
    }
  }

  private func icon(_ status: String) -> String {
    switch status.lowercased() {
    case let s where s.contains("input"): return "questionmark.bubble.fill"
    case let s where s.contains("done"): return "checkmark.circle.fill"
    case let s where s.contains("fail"), let s where s.contains("error"): return "xmark.octagon.fill"
    default: return "terminal.fill"
    }
  }
  private func tint(_ status: String) -> Color {
    switch status.lowercased() {
    case let s where s.contains("input"): return .yellow
    case let s where s.contains("done"): return .green
    case let s where s.contains("fail"), let s where s.contains("error"): return .red
    default: return .blue
    }
  }
  private func short(_ status: String) -> String {
    let s = status.lowercased()
    if s.contains("input") { return "?" }
    if s.contains("done") { return "✓" }
    if s.contains("fail") || s.contains("error") { return "✗" }
    return "•"
  }
}
