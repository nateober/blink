import XCTest
@testable import FleetCore

final class AppearanceRulesTests: XCTestCase {
  func testStyleWithoutDarkThemeUsesOneThemeEverywhere() {
    XCTAssertEqual(AppearanceRules.themeName(light: "Solarized Light", dark: nil, isDark: true), "Solarized Light")
    XCTAssertEqual(AppearanceRules.themeName(light: "Solarized Light", dark: "", isDark: true), "Solarized Light")
  }

  func testDarkThemeIsUsedOnlyInDarkMode() {
    XCTAssertEqual(AppearanceRules.themeName(light: "Light", dark: "Monokai", isDark: true), "Monokai")
    XCTAssertEqual(AppearanceRules.themeName(light: "Light", dark: "Monokai", isDark: false), "Light")
  }

  func testForcedLookBeatsTheSystem() {
    XCTAssertTrue(AppearanceRules.isDark(override: .dark, systemIsDark: false))
    XCTAssertFalse(AppearanceRules.isDark(override: .light, systemIsDark: true))
    XCTAssertTrue(AppearanceRules.isDark(override: .system, systemIsDark: true))
    XCTAssertFalse(AppearanceRules.isDark(override: .system, systemIsDark: false))
  }
}
