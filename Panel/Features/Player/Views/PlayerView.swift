import AppKit
import SwiftUI

struct PlayerView: View {
    @Environment(PlayerStore.self) private var store

    var body: some View {
        Group {
            if let snapshot = store.presentedSnapshot {
                activeContent(snapshot, isReconnecting: store.isReconnecting)
            } else {
                switch store.state {
                case .idle:
                    idleContent
                case .active:
                    EmptyView()
                case .unavailable:
                    unavailableContent
                }
            }
        }
        .frame(width: 300, height: 100, alignment: .leading)
    }

    private func activeContent(
        _ snapshot: NowPlayingSnapshot,
        isReconnecting: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            artwork(snapshot.artworkData)
                .overlay(alignment: .topTrailing) {
                    if isReconnecting {
                        ReconnectingMarker()
                            .padding(8)
                    }
                }

            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(snapshot.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(snapshot.displaySubtitle ?? snapshot.source.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 180)

                playbackControls(isPlaying: snapshot.isPlaying)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func artwork(_ data: Data?) -> some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.indigo.opacity(0.22))
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
        }
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(15)
        .frame(width: 100, height: 100)
    }

    private func playbackControls(isPlaying: Bool) -> some View {
        HStack(spacing: 24) {
            controlButton(
                "Previous",
                systemImage: "backward.end.fill",
                action: store.playPrevious
            )

            controlButton(
                isPlaying ? "Pause" : "Play",
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                action: store.togglePlayback
            )

            controlButton(
                "Next",
                systemImage: "forward.end.fill",
                action: store.playNext
            )

            if let error = store.playbackCommandError {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .help(error)
                    .accessibilityLabel("Playback command failed")
            }
        }
        .allowsHitTesting(!store.isPerformingPlaybackCommand)
    }

    private var idleContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing Playing")
                    .font(.system(size: 15, weight: .semibold))
                Text("Start media to show it here")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
    }

    private var unavailableContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) {
                Text("Player Unavailable")
                    .font(.system(size: 14, weight: .semibold))
                Button("Retry", action: store.retry)
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 18)
    }

    private func controlButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ReconnectingMarker: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.orange.opacity(0.65), lineWidth: 1)
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.7 : 0.8)
                .opacity(isPulsing ? 0 : 0.9)

            Circle()
                .fill(.orange)
                .frame(width: 5, height: 5)
                .shadow(color: .orange.opacity(0.7), radius: 3)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(.easeOut(duration: 1.15).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .help("Reconnecting to media helper")
        .accessibilityLabel("Reconnecting to media helper")
    }
}

#if DEBUG
#Preview("Player — active") {
    ZStack {
        PanelShape()
            .fill(.black)
            .frame(width: 240, height: 100)
        PlayerView()
    }
    .frame(width: 300, height: 200, alignment: .bottom)
    .environment(makePreviewPlayerStore())
}
#endif
