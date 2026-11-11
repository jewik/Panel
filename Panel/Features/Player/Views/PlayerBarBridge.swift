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
