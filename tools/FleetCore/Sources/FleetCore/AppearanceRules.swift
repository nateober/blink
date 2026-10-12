import Foundation

// Pure rules for following the system appearance: which theme a style uses in
// Light and Dark Mode, and whether the interface counts as dark.
public enum AppearanceRules {
  /// What the user picked for the app's look, as stored in the keyboard style setting.
  public enum Override { case system, light, dark }

  /// A forced look wins; otherwise the system decides.
  public static func isDark(override: Override, systemIsDark: Bool) -> Bool {
    switch override {
    case .light: return false
    case .dark: return true
    case .system: return systemIsDark
    }
  }

  /// A style without a dark theme (nil or empty) uses its one theme in both modes.
  public static func themeName(light: String, dark: String?, isDark: Bool) -> String {
    guard isDark, let dark, !dark.isEmpty else { return light }
    return dark
  }
}
