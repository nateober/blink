//////////////////////////////////////////////////////////////////////////////////
//
// B L I N K  —  fleet-native fork  ·  WIDGET EXTENSION
//
// Widget bundle entry point. Set this type as the @main of the widget-extension target
// (Xcode's template generates a similar file — replace its body with this).
// See docs/LIVE-ACTIVITY-SETUP.md.
//
//////////////////////////////////////////////////////////////////////////////////

import SwiftUI
import WidgetKit

@main
struct BlinkWidgetsBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      FleetActivityWidget()
    }
  }
}
