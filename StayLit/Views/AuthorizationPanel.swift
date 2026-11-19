import StayLitCore
import SwiftUI

/// Replaces the switch while the sudoers rule is missing: says why, shows the exact rule,
/// and offers to install it.
struct AuthorizationPanel: View {
    let model: AppModel
    @State private var showsRule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stay Lit needs your permission to change the sleep setting. Installing adds a rule that lets it run two pmset commands without a password. macOS asks for an administrator password once.")
                .subheadlineStyle()
                .foregroundStyle(.secondary)
            DisclosureGroup("Show the rule", isExpanded: $showsRule) {
                Text(model.authorizationRuleText)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(.subheadline)
            .accessibilityIdentifier("authorizationRuleDisclosure")
            Button("Install…") {
                Task { await model.installAuthorization() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy)
            .accessibilityIdentifier("installAuthorizationButton")
        }
    }
}
