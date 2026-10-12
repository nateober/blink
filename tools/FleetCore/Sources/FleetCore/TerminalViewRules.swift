import Foundation

// Pure rules for two terminal view behaviours: when the scroll view follows new output,
// and when a size change is passed on to the session.

public enum ScrollRules {
  /// New output grew the content. The view follows it to the bottom only if it was already
  /// there (within a point) and the user is not scrolling.
  public static func followsNewContent(offsetY: Double, contentHeight: Double, viewHeight: Double, userIsScrolling: Bool) -> Bool {
    guard !userIsScrolling else { return false }
    return offsetY >= max(contentHeight - viewHeight, 0) - 1
  }
}

public enum ResizeRules {
  /// Seconds to wait after the scene becomes active before reporting a held size change.
  public static let settleDelay: Double = 0.6

  /// Size changes while the scene is not active come from the keyboard hiding and showing;
  /// they wait until the scene is active again.
  public static func defersResize(sceneIsActive: Bool) -> Bool {
    !sceneIsActive
  }
}
