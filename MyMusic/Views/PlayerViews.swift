import SwiftUI

/// Мини-плеер внизу экрана.
struct MiniPlayerBar: View {
    @Environment(PlayerService.self) private var player
    @State private var showFull = false

    var body: some View {
        if let song = player.current {
            HStack(spacing: 12) {
                ArtworkView(song: song, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.subheadline).lineLimit(1)
                    Text(player.errorMessage ?? song.artist)
                        .font(.caption)
                        .foregroundStyle(player.errorMessage == nil ? Color.secondary : Color.red)
                        .lineLimit(1)
                }
                Spacer()
                if player.isLoading {
                    ProgressView().frame(width: 32)
                } else {
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3).frame(width: 32)
                    }
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .disabled(!player.hasNext)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .onTapGesture { showFull = true }
            .sheet(isPresented: $showFull) { NowPlayingView() }
        }
    }
}

/// Полноэкранный плеер.
struct NowPlayingView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var context
    @State private var scrubbing: Double?
    @MainActor private var downloads: DownloadService { .shared }

    var body: some View {
        if let song = player.current {
            VStack(spacing: 24) {
                Capsule().fill(.secondary).frame(width: 40, height: 5).padding(.top, 8)
                Spacer()
                ArtworkView(song: song, size: 300).shadow(radius: 12)
                VStack(spacing: 6) {
                    Text(song.title).font(.title3.bold()).multilineTextAlignment(.center).lineLimit(2)
                    Text(song.artist).foregroundStyle(.secondary)
                    if let error = player.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal)

                VStack(spacing: 4) {
                    Slider(
                        value: Binding(get: { scrubbing ?? player.currentTime },
                                       set: { scrubbing = $0 }),
                        in: 0...max(player.duration, 1),
                        onEditingChanged: { editing in
                            if !editing, let value = scrubbing {
                                player.seek(to: value)
                                scrubbing = nil
                            }
                        }
                    )
                    HStack {
                        Text(format(scrubbing ?? player.currentTime))
                        Spacer()
                        Text(format(player.duration))
                    }
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal, 24)

                HStack(spacing: 48) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    Button { player.togglePlayPause() } label: {
                        if player.isLoading {
                            ProgressView().frame(width: 64, height: 64)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 64))
                        }
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                        .disabled(!player.hasNext)
                }
                .font(.title)
                .buttonStyle(.plain)

                HStack(spacing: 40) {
                    let saved = Library.isSaved(song, in: context)
                    Button { Library.setSaved(song, !saved, in: context) } label: {
                        Image(systemName: saved ? "heart.fill" : "heart")
                    }
                    if downloads.inProgress.contains(song.id) {
                        ProgressView()
                    } else if downloads.isDownloaded(song.id) {
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
                    } else {
                        Button {
                            Library.setSaved(song, true, in: context)
                            Task { try? await downloads.download(song) }
                        } label: { Image(systemName: "arrow.down.circle") }
                    }
                    Menu {
                        SongMenu(song: song)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                .font(.title2)
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom)
        } else {
            ContentUnavailableView("Ничего не играет", systemImage: "music.note")
        }
    }

    private func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
