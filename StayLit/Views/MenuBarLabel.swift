import StayLitCore
import SwiftUI

/// The menu bar icon: a laptop with Zs while sleep is allowed, a laptop with a bolt while it is
/// blocked. Both are custom symbols of the asset catalog.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        Label {
            Text("Stay Lit")
        } icon: {
            Image(model.isSleepDisabled ? "laptop.closed.bolt" : "laptop.closed.zzz")
        }
        .labelStyle(.iconOnly)
    }
}
