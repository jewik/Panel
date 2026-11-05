import AppKit
import SwiftUI

struct PlayerView: View {
    @Environment(PlayerStore.self) private var store

    var body: some View {
        Group {
            switch store.state {
            case .idle:
                idleContent
            case .active(let snapshot):
                activeContent(snapshot)
            case .unavailable:
                unavailableContent
            }
        }
        .frame(width: 240, height: 100, alignment: .leading)
    }

    private func activeContent(_ snapshot: NowPlayingSnapshot) -> some View {
        HStack(alignment: .center, spacing: 0) {
            artwork(snapshot.artworkData)

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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .disabled(store.isPerformingPlaybackCommand)
        .opacity(store.isPerformingPlaybackCommand ? 0.55 : 1)
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
                .font(.system(size: 16, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
