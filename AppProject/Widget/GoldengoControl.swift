import WidgetKit
import SwiftUI
import AppIntents
import GoldengoIntents

@available(iOS 18.0, *)
struct GoldengoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "GoldengoQuickAddControl") {
            ControlWidgetButton(action: OpenQuickAddIntent()) {
                Label("Add expense", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add expense")
        .description("Jump straight to Goldengo Quick-Add.")
    }
}
