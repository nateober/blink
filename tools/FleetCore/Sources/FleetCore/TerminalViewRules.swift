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

extension ScrollRules {
  /// Whether a move of the scroll view is passed on to the page. While the grid is held
  /// (the app is not active) only moves made for the page count; the rest are the scroll
  /// view refitting itself to a size the page is not drawing for.
  public static func reportsScroll(gridHeld: Bool, movedForPage: Bool) -> Bool {
    !gridHeld || movedForPage
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

  /// Whether a held or deferred size change may be released now. `sceneState` is nil when
  /// the view is in no window (nothing left to wait for), otherwise whether its scene is
  /// active. An inactive scene keeps waiting; its next activation tries again.
  public static func settles(sceneState: Bool?) -> Bool {
    sceneState ?? true
  }
}
