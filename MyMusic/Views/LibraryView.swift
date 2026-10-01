import SwiftUI
import SwiftData

/// Сохранённая музыка.
struct LibraryView: View {
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Track> { $0.isSaved == true }, sort: \Track.addedAt, order: .reverse)
    private var tracks: [Track]
    @State private var onlyDownloaded = false
    @MainActor private var downloads: DownloadService { .shared }

    private var songs: [Song] {
        let all = tracks.map(\.song)
        return onlyDownloaded ? all.filter { downloads.isDownloaded($0.id) } : all
    }

    var body: some View {
        List {
            Picker("Фильтр", selection: $onlyDownloaded) {
                Text("Все").tag(false)
                Text("Скачанные").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowSeparator(.hidden)

            if !songs.isEmpty {
                HStack {
                    Button("Слушать", systemImage: "play.fill") { player.play(songs) }
                    Spacer()
                    Button("Перемешать", systemImage: "shuffle") { player.play(songs.shuffled()) }
                }
                .buttonStyle(.bordered)
                .listRowSeparator(.hidden)
            }

            ForEach(Array(songs.enumerated()), id: \.element.id) { i, song in
                SongRow(song: song)
                    .onTapGesture { player.play(songs, startAt: i) }
                    .swipeActions {
                        Button("Убрать", systemImage: "heart.slash", role: .destructive) {
                            Library.setSaved(song, false, in: context)
                        }
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView("Пока пусто", systemImage: "heart",
                                       description: Text("Удерживайте трек в поиске, чтобы сохранить или скачать его"))
            }
        }
        .navigationTitle("Медиатека")
    }
}
