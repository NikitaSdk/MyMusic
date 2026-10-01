import SwiftUI
import SwiftData

/// Обложка: сначала из локального файла (работает офлайн), иначе из сети.
struct ArtworkView: View {
    let song: Song
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: DownloadService.thumbURL(for: song.id).path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: URL(string: song.thumbnailURL)) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            Color.secondary.opacity(0.2)
                            Image(systemName: "music.note").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12))
    }
}

/// Строка трека в списке.
struct SongRow: View {
    let song: Song
    @Environment(PlayerService.self) private var player
    @MainActor private var downloads: DownloadService { .shared }
    @MainActor private var network: NetworkMonitor { .shared }

    private var isAvailable: Bool { network.isOnline || downloads.isDownloaded(song.id) }

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(song: song)
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .lineLimit(1)
                    .fontWeight(player.current?.id == song.id ? .semibold : .regular)
                    .foregroundStyle(player.current?.id == song.id ? Color.accentColor : .primary)
                Text(song.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if downloads.inProgress.contains(song.id) {
                ProgressView()
            } else if downloads.isDownloaded(song.id) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.green)
            }
            Text(song.duration).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .opacity(isAvailable ? 1 : 0.4)
        .contentShape(Rectangle())
        .contextMenu { SongMenu(song: song) }
    }
}

/// Действия с треком: сохранить, скачать, добавить в плейлист.
struct SongMenu: View {
    let song: Song
    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @MainActor private var downloads: DownloadService { .shared }

    var body: some View {
        if Library.isSaved(song, in: context) {
            Button("Убрать из медиатеки", systemImage: "heart.slash") {
                Library.setSaved(song, false, in: context)
            }
        } else {
            Button("В медиатеку", systemImage: "heart") {
                Library.setSaved(song, true, in: context)
            }
        }

        if downloads.isDownloaded(song.id) {
            Button("Удалить загрузку", systemImage: "trash", role: .destructive) {
                downloads.remove(song.id)
            }
        } else if !downloads.inProgress.contains(song.id) {
            Button("Скачать", systemImage: "arrow.down.circle") {
                Library.setSaved(song, true, in: context)   // скачанное всегда в медиатеке
                Task { try? await downloads.download(song) }
            }
        }

        Menu("Добавить в плейлист", systemImage: "text.badge.plus") {
            if playlists.isEmpty {
                Text("Сначала создайте плейлист")
            }
            ForEach(playlists) { playlist in
                Button(playlist.name) { Library.add(song, to: playlist, in: context) }
            }
        }
    }
}
