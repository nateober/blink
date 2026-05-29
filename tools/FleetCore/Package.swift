// swift-tools-version:5.9
import PackageDescription

// FleetCore: pure, UIKit-free logic for the fleet-native Blink features
// (mount bookmarks, push payloads/token store). Tested Mac-native via `swift test`.
// The same source files are also compiled into the Blink `BlinkConfig` framework
// target via Xcode project references — this package is the single source of truth.
let package = Package(
  name: "FleetCore",
  platforms: [.macOS(.v12), .iOS(.v16)],
  products: [
    .library(name: "FleetCore", targets: ["FleetCore"])
  ],
  targets: [
    .target(name: "FleetCore"),
    .testTarget(name: "FleetCoreTests", dependencies: ["FleetCore"])
  ]
)
