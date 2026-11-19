//
//  PlayerAutoSlidingText.swift
//  Panel
//
//  Created by Usanin Ivan on 13.11.2026.
//

import SwiftUI

@MainActor
final class PlayerAutoSlidingTextSynchronizationMarker {
    fileprivate struct Timing: Equatable {
        let movementDuration: TimeInterval
        let startDelay: TimeInterval
        let endDelay: TimeInterval
    }

    private var timings: [UUID: Timing] = [:]

    fileprivate private(set) var cycleStart = Date.now
    fileprivate private(set) var movementDuration: TimeInterval = 0
    fileprivate private(set) var startDelay: TimeInterval = 0
    fileprivate private(set) var endDelay: TimeInterval = 0

    /// Restarts every attached text on the same timeline.
    func start(at date: Date = .now) {
        cycleStart = date
    }

    fileprivate func update(_ timing: Timing, for id: UUID) {
        guard timings[id] != timing else { return }
        timings[id] = timing
        updateSharedTiming()
    }

    fileprivate func remove(_ id: UUID) {
        guard timings.removeValue(forKey: id) != nil else { return }
        updateSharedTiming()
    }

    private func updateSharedTiming() {
        movementDuration = timings.values.map(\.movementDuration).max() ?? 0
        startDelay = timings.values.map(\.startDelay).max() ?? 0
        endDelay = timings.values.map(\.endDelay).max() ?? 0
        start()
    }
}

struct PlayerAutoSlidingText: View {
    private let text: String
    private let spacing: CGFloat
    private let pointsPerSecond: CGFloat
    private let startDelay: TimeInterval
    private let endDelay: TimeInterval
    private let edgeFadeWidth: CGFloat
    private let synchronizationMarker: PlayerAutoSlidingTextSynchronizationMarker?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var synchronizationID = UUID()
    @State private var availableWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var animationStart = Date.now

    init(
        _ text: String,
        spacing: CGFloat = 24,
        pointsPerSecond: CGFloat = 30,
        startDelay: TimeInterval = 1.25,
        endDelay: TimeInterval = 0.75,
        edgeFadeWidth: CGFloat = 8,
        synchronizationMarker: PlayerAutoSlidingTextSynchronizationMarker? = nil
    ) {
        self.text = text
        self.spacing = max(0, spacing)
        self.pointsPerSecond = max(1, pointsPerSecond)
        self.startDelay = max(0, startDelay)
        self.endDelay = max(0, endDelay)
        self.edgeFadeWidth = max(0, edgeFadeWidth)
        self.synchronizationMarker = synchronizationMarker
    }

    var body: some View {
        Text(text)
            .lineLimit(1)
            .opacity(shouldScroll ? 0 : 1)
            .accessibilityHidden(shouldScroll)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if shouldScroll {
                    scrollingText
                }
            }
            .background {
                measurementText
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { newWidth in
                updateAvailableWidth(newWidth)
            }
            .clipped()
            .onChange(of: text) {
                restartAnimation()
            }
            .onChange(of: reduceMotion) {
                updateSynchronizationTiming()
            }
            .onAppear {
                updateSynchronizationTiming()
            }
            .onDisappear {
                synchronizationMarker?.remove(synchronizationID)
            }
            .animation(.smooth(duration: 0.2), value: text)
    }

    private var shouldScroll: Bool {
        !reduceMotion && availableWidth > 0 && textWidth > availableWidth + 0.5
    }

    private var scrollingText: some View {
        TimelineView(.animation) { context in
            let offset = horizontalOffset(at: context.date)
            let distance = textWidth + spacing
            let fadeTransitionDistance = pointsPerSecond * 0.2
            let fadeProgress = min(
                1,
                min(
                    abs(offset) / fadeTransitionDistance,
                    abs(offset + distance) / fadeTransitionDistance
                )
            )

            ZStack(alignment: .leading) {
                HStack(spacing: spacing) {
                    singleLineText
                    singleLineText
                }
                .offset(x: offset)
            }
            .frame(width: availableWidth, alignment: .leading)
            .mask {
                edgeFadeMask(progress: fadeProgress)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }

    private var measurementText: some View {
        singleLineText
            .hidden()
            .accessibilityHidden(true)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { newWidth in
                updateTextWidth(newWidth)
            }
    }

    private var singleLineText: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func horizontalOffset(at date: Date) -> CGFloat {
        let distance = textWidth + spacing
        let ownMovementDuration = TimeInterval(distance / pointsPerSecond)
        let sharedMovementDuration = synchronizationMarker?.movementDuration
            ?? ownMovementDuration
        let sharedStartDelay = synchronizationMarker?.startDelay ?? startDelay
        let sharedEndDelay = synchronizationMarker?.endDelay ?? endDelay
        let sharedCycleStart = synchronizationMarker?.cycleStart ?? animationStart
        let cycleDuration = sharedStartDelay
            + sharedMovementDuration
            + sharedEndDelay

        guard distance > 0, ownMovementDuration > 0, cycleDuration > 0 else {
            return 0
        }

        let elapsed = max(0, date.timeIntervalSince(sharedCycleStart))
        let cycleTime = elapsed.truncatingRemainder(dividingBy: cycleDuration)

        if cycleTime <= sharedStartDelay {
            return 0
        }

        if cycleTime >= sharedStartDelay + ownMovementDuration {
            return -distance
        }

        let progress = (cycleTime - sharedStartDelay) / ownMovementDuration
        return -distance * CGFloat(progress)
    }

    private func edgeFadeMask(progress: CGFloat) -> some View {
        let fadeFraction = min(0.25, edgeFadeWidth / max(1, availableWidth))
        let edgeOpacity = 1 - progress

        return LinearGradient(
            stops: [
                .init(color: .black.opacity(edgeOpacity), location: 0),
                .init(color: .black, location: fadeFraction),
                .init(color: .black, location: 1 - fadeFraction),
                .init(color: .black.opacity(edgeOpacity), location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func updateAvailableWidth(_ newWidth: CGFloat) {
        guard abs(availableWidth - newWidth) > 0.5 else { return }
        availableWidth = newWidth
        updateSynchronizationTiming()
    }

    private func updateTextWidth(_ newWidth: CGFloat) {
        guard abs(textWidth - newWidth) > 0.5 else { return }
        textWidth = newWidth
        updateSynchronizationTiming()
    }

    private func restartAnimation() {
        if let synchronizationMarker {
            synchronizationMarker.start()
        } else {
            animationStart = .now
        }
    }

    private func updateSynchronizationTiming() {
        guard let synchronizationMarker else {
            restartAnimation()
            return
        }

        let movementDuration = shouldScroll
            ? TimeInterval((textWidth + spacing) / pointsPerSecond)
            : 0

        synchronizationMarker.update(
            .init(
                movementDuration: movementDuration,
                startDelay: startDelay,
                endDelay: endDelay
            ),
            for: synchronizationID
        )
    }
}

#if DEBUG
#Preview("Player auto-sliding text") {
    VStack(alignment: .leading, spacing: 16) {
        PlayerAutoSlidingText("Short title")

        PlayerAutoSlidingText(
            "A very long track title that does not fit into the available width"
        )
    }
    .font(.system(size: 16, weight: .semibold))
    .foregroundStyle(.white)
    .frame(width: 180)
    .padding()
    .background(.black)
}
#endif
