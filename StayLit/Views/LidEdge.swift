import StayLitCore
import SwiftUI

/// The colors stay here: the core only knows what each light stands for.
extension LidLight {
    var color: Color {
        switch self {
        case .working: Color(.lightGreen)
        case .waiting: Color(.lightAmber)
        case .steady: Color(.lightWhite)
        }
    }
}

/// The front edge of a closed MacBook, drawn: the lid on the base, the opening notch, and the
/// row of lights on the base. Unlit, the Mac sleeps when the lid closes; lit, it stays on.
/// The lights are the window's one animation: they fade up when they come on, then the
/// working ones breathe. Reduce Motion keeps them still.
struct LidEdge: View {
    let lights: [LidLight]
    let isLit: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let lidHeight: CGFloat = 4.5
    private static let seamHeight: CGFloat = 0.5
    private static let baseHeight: CGFloat = 9
    /// Room under the base for its shadow and the lights' reflection on the table.
    private static let tableHeight: CGFloat = 8
    private static let lightsInset: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topTrailing) {
            slab
            HStack(spacing: 7) {
                ForEach(Array(lights.enumerated()), id: \.offset) { _, light in
                    LightView(light: light, isLit: isLit, reduceMotion: reduceMotion)
                }
            }
            .padding(.top, Self.lidHeight + Self.seamHeight + (Self.baseHeight - LightView.size) / 2)
            .padding(.trailing, Self.lightsInset)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.lidHeight + Self.seamHeight + Self.baseHeight + Self.tableHeight, alignment: .top)
        .accessibilityHidden(true)
    }

    private var slab: some View {
        // One gradient over the lid and the base: the light falls on the whole slab from above.
        LinearGradient(
            colors: [Color(.lidAluminiumTop), Color(.lidAluminiumBottom)],
            startPoint: .top,
            endPoint: .bottom
        )
        .mask {
            VStack(spacing: 0) {
                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                    .frame(height: Self.lidHeight + Self.seamHeight)
                UnevenRoundedRectangle(bottomLeadingRadius: 4.5, bottomTrailingRadius: 4.5)
                    .frame(height: Self.baseHeight)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.lightWell))
                .frame(height: Self.seamHeight)
                .padding(.top, Self.lidHeight)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 2.5, bottomTrailingRadius: 2.5)
                .fill(Color(.lightWell).opacity(0.7))
                .frame(width: 34, height: 2.5)
                .padding(.top, Self.lidHeight + Self.seamHeight)
        }
        .frame(height: Self.lidHeight + Self.seamHeight + Self.baseHeight)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 2)
    }
}

/// One light: a socket always, and when lit a bright core, its glow and a faint reflection
/// on the table under the base.
private struct LightView: View {
    let light: LidLight
    let isLit: Bool
    let reduceMotion: Bool

    static let size: CGFloat = 5
    /// From the centre of the light down to the table under the base.
    private static let tableOffset: CGFloat = 7

    var body: some View {
        Circle()
            .fill(Color(.lightWell))
            .overlay {
                glow
                    .opacity(isLit ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isLit)
            }
            .frame(width: Self.size, height: Self.size)
    }

    @ViewBuilder private var glow: some View {
        if isLit, light == .working, !reduceMotion {
            lit.phaseAnimator([1.0, 0.55]) { content, intensity in
                content.opacity(intensity)
            } animation: { _ in
                .easeInOut(duration: 2)
            }
        } else {
            lit
        }
    }

    private var lit: some View {
        Circle()
            .fill(light.color)
            .padding(0.5)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 2, height: 2)
                    .blur(radius: 0.4)
            }
            .background {
                Circle()
                    .fill(light.color)
                    .frame(width: 12, height: 12)
                    .blur(radius: 3)
                    .opacity(0.8)
            }
            .background {
                Ellipse()
                    .fill(light.color)
                    .frame(width: 9, height: 2.5)
                    .blur(radius: 1.5)
                    .opacity(0.3)
                    .offset(y: Self.tableOffset)
            }
    }
}

#Preview("Lid edge") {
    VStack(spacing: 16) {
        LidEdge(lights: [.steady], isLit: false)
        LidEdge(lights: [.steady], isLit: true)
        LidEdge(lights: LidLight.row(for: ClaudeSessionCounts(working: 3, waiting: 1)), isLit: true)
    }
    .padding(16)
    .frame(width: 320)
}
