import SwiftUI

struct PlayerArtworkIdentity: Hashable {
    private let byteCount: Int
    private let prefix: Data
    private let middle: Data
    private let suffix: Data

    init(data: Data?) {
        let data = data ?? Data()
        byteCount = data.count
        prefix = Data(data.prefix(24))

        let middleIndex = max(0, data.count / 2 - 12)
        middle = Data(data.dropFirst(middleIndex).prefix(24))
        suffix = Data(data.suffix(24))
    }
}

extension View {
    func playerArtworkFlip(identity: PlayerArtworkIdentity) -> some View {
        modifier(PlayerArtworkFlipModifier(identity: identity))
    }
}

private struct PlayerArtworkFlipModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let identity: PlayerArtworkIdentity

    func body(content: Content) -> some View {
        ZStack {
            content
                .id(identity)
                .transition(reduceMotion ? .opacity : .playerArtworkFlip)
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.18)
                : .easeInOut(duration: 0.45),
            value: identity
        )
    }
}

private struct PlayerArtworkFlipEffect: ViewModifier {
    let angle: Double
    let opacity: Double
    let blurRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.7
            )
            .blur(radius: blurRadius)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var playerArtworkFlip: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: PlayerArtworkFlipEffect(
                    angle: -90,
                    opacity: 0,
                    blurRadius: 10
                ),
                identity: PlayerArtworkFlipEffect(
                    angle: 0,
                    opacity: 1,
                    blurRadius: 0
                )
            ),
            removal: .modifier(
                active: PlayerArtworkFlipEffect(
                    angle: 90,
                    opacity: 0,
                    blurRadius: 10
                ),
                identity: PlayerArtworkFlipEffect(
                    angle: 0,
                    opacity: 1,
                    blurRadius: 0
                )
            )
        )
    }
}
