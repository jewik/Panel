import AppKit
import SwiftUI

struct PlayerBarBridge: View {
    @Environment(PlayerStore.self) private var store

    @Binding var value: Double
    @Binding var isSliderActive: Bool
    @Binding var accentColor: Color
    @Binding var isSliderDragging: Bool

    @State private var isUsingDefaultStyle = true
    @State private var artworkIdentity: ArtworkIdentity?
    @State private var pendingSeekValue: Double?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                while !Task.isCancelled {
                    synchronize(at: .now)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            .onChange(of: value) { _, newValue in
                guard isSliderDragging else { return }
                pendingSeekValue = newValue
            }
            .onChange(of: isSliderDragging) { wasDragging, isDragging in
                if isDragging {
                    pendingSeekValue = value
                    return
                }

                guard wasDragging else { return }
                defer { pendingSeekValue = nil }
                guard isSliderActive else { return }
                store.seek(toProgress: pendingSeekValue ?? value)
            }
    }

    private func synchronize(at date: Date) {
        guard let snapshot = store.presentedSnapshot,
              snapshot.isPlaying,
              let duration = snapshot.duration,
              duration.isFinite,
              duration > 0 else {
            applyDefaultStyle()
            return
        }

        if isUsingDefaultStyle {
            isUsingDefaultStyle = false
            isSliderActive = true
        }

        let currentArtworkIdentity = ArtworkIdentity(snapshot: snapshot)
        if currentArtworkIdentity != artworkIdentity {
            artworkIdentity = currentArtworkIdentity
            accentColor = ArtworkAccentColor.color(from: snapshot.artworkData)
        }

        guard !isSliderDragging else { return }
        value = min(max(0, snapshot.elapsed(at: date) / duration), 1)
    }

    private func applyDefaultStyle() {
        guard !isUsingDefaultStyle else { return }
        isUsingDefaultStyle = true
        artworkIdentity = nil
        isSliderActive = false
        accentColor = .white
        value = 1
    }
}

private struct ArtworkIdentity: Equatable {
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

private enum ArtworkAccentColor {
    private static let sampleSize = 24

    static func color(from data: Data?) -> Color {
        guard let data,
              let image = NSImage(data: data),
              let bitmap = sampledBitmap(from: image) else { return .white }

        var buckets = Array(repeating: ColorBucket(), count: 24)

        for x in 0..<sampleSize {
            for y in 0..<sampleSize {
                guard let color = bitmap.colorAt(x: x, y: y)?
                    .usingColorSpace(.deviceRGB) else { continue }

                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                color.getHue(
                    &hue,
                    saturation: &saturation,
                    brightness: &brightness,
                    alpha: &alpha
                )

                guard alpha > 0.25, brightness > 0.08 else { continue }
                let bucketIndex = min(Int(hue * CGFloat(buckets.count)), buckets.count - 1)
                let weight = alpha * (0.25 + saturation * 1.5) * (0.5 + brightness)
                buckets[bucketIndex].add(color, weight: weight)
            }
        }

        guard let winner = buckets.max(by: { $0.weight < $1.weight }),
              winner.weight > 0 else { return .white }
        return winner.color
    }

    private static func sampledBitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: sampleSize,
            pixelsHigh: sampleSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .medium
        image.draw(
            in: NSRect(x: 0, y: 0, width: sampleSize, height: sampleSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}

private struct ColorBucket {
    private(set) var red: CGFloat = 0
    private(set) var green: CGFloat = 0
    private(set) var blue: CGFloat = 0
    private(set) var weight: CGFloat = 0

    mutating func add(_ color: NSColor, weight newWeight: CGFloat) {
        red += color.redComponent * newWeight
        green += color.greenComponent * newWeight
        blue += color.blueComponent * newWeight
        weight += newWeight
    }

    var color: Color {
        guard weight > 0 else { return .white }
        return Color(
            red: Double(red / weight),
            green: Double(green / weight),
            blue: Double(blue / weight)
        )
    }
}
