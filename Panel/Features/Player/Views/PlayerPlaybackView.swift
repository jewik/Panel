import AppKit
import SwiftUI

struct PlayerPlaybackView: View {
    @Environment(PlayerStore.self) private var store

    @State private var value: Double = 0
    @State private var duration: TimeInterval = 0
    @State private var elapsedTime: TimeInterval = 0
    @State private var accentColor: Color = .white
    @State private var artworkIdentity: PlaybackArtworkIdentity?
    @State private var isSliderActive = false
    @State private var isSliderDragging = false
    @State private var isHovered = false
    @State private var isPressing = false
    @State private var startValue: Double = 0

    private var activeColor: Color { accentColor }
    private var defaultColor: Color { accentColor.opacity(0.5) }
    private var backgroundColor: Color { accentColor.opacity(0.2) }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            
            Text(Self.formattedTime(elapsedTime))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.custsecondary)
//                .padding(.horizontal, 3)
            
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                let fillWidth = CGFloat(value) * totalWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(backgroundColor)

                    Rectangle()
                        .fill(isHovered || isPressing ? activeColor : defaultColor)
                        .frame(width: max(0, fillWidth))
                }
                .clipShape(Capsule())
                .gesture(dragGesture(totalWidth: totalWidth))
            }
            .frame(height: isSliderActive && (isHovered || isPressing) ? 8 : 5)
//            .frame(height: 8)
            .onHover { isHovered = $0 }

            Text("-\(Self.formattedTime(max(0, duration - elapsedTime)))")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.custsecondary)

        }
        .frame(width: 180, height: 10)
        
        .task {
            while !Task.isCancelled {
                synchronize(at: .now)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .animation(.smooth(duration: 0.2), value: value)
        .animation(.smooth(duration: 0.2), value: isHovered)
        .animation(.smooth(duration: 0.2), value: isPressing)
        .animation(.smooth(duration: 0.2), value: isSliderActive)
        .animation(.smooth(duration: 0.2), value: accentColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(Self.formattedTime(elapsedTime)) of \(Self.formattedTime(duration))"
        )
    }

    private func dragGesture(totalWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                guard isSliderActive, totalWidth > 0 else { return }

                if !isPressing {
                    isPressing = true
                    isSliderDragging = true
                    startValue = value
                }

                let delta = Double(gesture.translation.width / totalWidth)
                value = min(max(0, startValue + delta), 1)
                elapsedTime = duration * value
            }
            .onEnded { _ in
                guard isPressing else { return }
                isPressing = false
                isSliderDragging = false
                store.seek(toProgress: value)
            }
    }

    private func synchronize(at date: Date) {
        guard let snapshot = store.presentedSnapshot,
              let snapshotDuration = snapshot.duration,
              snapshotDuration.isFinite,
              snapshotDuration > 0 else {
            reset()
            return
        }

        isSliderActive = true
        duration = snapshotDuration

        let currentArtworkIdentity = PlaybackArtworkIdentity(snapshot: snapshot)
        if currentArtworkIdentity != artworkIdentity {
            artworkIdentity = currentArtworkIdentity
            accentColor = PlaybackArtworkAccentColor.color(from: snapshot.artworkData)
        }

        guard !isSliderDragging else { return }
        elapsedTime = snapshot.elapsed(at: date)
        value = min(max(0, elapsedTime / snapshotDuration), 1)
    }

    private func reset() {
        guard isSliderActive || duration != 0 || elapsedTime != 0 || value != 0 else {
            return
        }

        isSliderActive = false
        isSliderDragging = false
        isPressing = false
        artworkIdentity = nil
        accentColor = .white
        duration = 0
        elapsedTime = 0
        value = 0
    }

    private static func formattedTime(_ time: TimeInterval) -> String {
        guard time.isFinite else { return "0:00" }

        let totalSeconds = Int(max(0, time).rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PlaybackArtworkIdentity: Equatable {
    let trackID: String
    let byteCount: Int
    let prefix: Data
    let suffix: Data

    init(snapshot: NowPlayingSnapshot) {
        let data = snapshot.artworkData ?? Data()
        trackID = snapshot.id
        byteCount = data.count
        prefix = Data(data.prefix(16))
        suffix = Data(data.suffix(16))
    }
}

private enum PlaybackArtworkAccentColor {
    static func color(from data: Data?) -> Color {
        guard let data,
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return .white }

        var pixel = [UInt8](repeating: 0, count: 4)
        let didDraw = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return false }

            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }

        guard didDraw else { return .white }

        let channels = pixel.prefix(3).map { Double($0) / 255 }
        guard let highest = channels.max(),
              let lowest = channels.min(),
              highest > 0.05 else { return .white }

        let range = highest - lowest
        guard range / highest >= 0.12 else { return .white }

        let stretched = channels.map {
            min(1, max(0, ($0 - lowest) / range * 0.86 + 0.06))
        }
        return Color(
            .sRGB,
            red: stretched[0],
            green: stretched[1],
            blue: stretched[2],
            opacity: 1
        )
    }
}

#if DEBUG
#Preview("Player playback") {
    PlayerPlaybackView()
        .padding()
        .background(.black)
        .environment(makePreviewPlayerStore())
}
#endif
