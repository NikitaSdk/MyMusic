import SwiftUI
import SwiftData

struct PlaylistsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Playlist.createdAt) private var playlists: [Playlist]
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(playlists) { playlist in
                NavigationLink(value: playlist) {
                    HStack {
                        Image(systemName: "music.note.list")
                            .frame(width: 48, height: 48)
                            .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                            Text("\(playlist.trackIds.count) треков").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                for i in offsets { context.delete(playlists[i]) }
                try? context.save()
            }
        }
        .listStyle(.plain)
        .overlay {
            if playlists.isEmpty {
                ContentUnavailableView("Нет плейлистов", systemImage: "music.note.list",
                                       description: Text("Нажмите «+», чтобы создать"))
            }
        }
        .navigationTitle("Плейлисты")
        .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
        .toolbar {
            Button("Новый", systemImage: "plus") { newName = ""; showingNew = true }
        }
        .alert("Новый плейлист", isPresented: $showingNew) {
            TextField("Название", text: $newName)
            Button("Создать") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                context.insert(Playlist(name: name))
                try? context.save()
            }
            Button("Отмена", role: .cancel) {}
        }
    }
}

struct PlaylistDetailView: View {
    @Bindable var playlist: Playlist
    @Environment(PlayerService.self) private var player
    @Environment(\.modelContext) private var context
    @Query private var allTracks: [Track]

    private var songs: [Song] {
        let byId = Dictionary(allTracks.map { ($0.videoId, $0) }, uniquingKeysWith: { a, _ in a })
        return playlist.trackIds.compactMap { byId[$0]?.song }
    }

    var body: some View {
        let songs = self.songs
        List {
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
            }
            .onDelete { offsets in
                playlist.trackIds.remove(atOffsets: offsets)
                try? context.save()
            }
            .onMove { from, to in
                playlist.trackIds.move(fromOffsets: from, toOffset: to)
                try? context.save()
            }
        }
        .listStyle(.plain)
        .overlay {
            if songs.isEmpty {
                ContentUnavailableView("Плейлист пуст", systemImage: "music.note",
                                       description: Text("Удерживайте трек в поиске → «Добавить в плейлист»"))
            }
        }
        .navigationTitle(playlist.name)
        .toolbar { EditButton() }
    }
}
