import SwiftUI

extension View {
    /// The small text under a setting, wrapped to the window width.
    func captionStyle() -> some View {
        font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The running text of the window outside the setting rows, wrapped to the window width.
    func subheadlineStyle() -> some View {
        font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension ShapeStyle where Self == AnyShapeStyle {
    /// Secondary, or amber when `alerted`: the condition behind it is what the window reports.
    static func secondary(alerted: Bool) -> AnyShapeStyle {
        alerted ? AnyShapeStyle(Color(.textAmber)) : AnyShapeStyle(.secondary)
    }
}
