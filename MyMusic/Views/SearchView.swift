import SwiftUI

struct SearchView: View {
    @Environment(PlayerService.self) private var player
    @State private var query = ""
    @State private var results: [Song] = []
    @State private var isSearching = false
    @State private var error: String?
    @MainActor private var network: NetworkMonitor { .shared }

    var body: some View {
        List {
            if !network.isOnline {
                Label("Нет интернета. Слушайте скачанное в «Медиатеке».", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            }
            if let error {
                Text(error).foregroundStyle(.red)
            }
            ForEach(Array(results.enumerated()), id: \.element.id) { i, song in
                SongRow(song: song)
                    .onTapGesture { player.play(results, startAt: i) }
            }
        }
        .listStyle(.plain)
        .overlay {
            if isSearching {
                ProgressView()
            } else if results.isEmpty && error == nil {
                ContentUnavailableView("Найдите музыку", systemImage: "music.magnifyingglass",
                                       description: Text("Введите название песни или исполнителя"))
            }
        }
        .navigationTitle("Поиск")
        .searchable(text: $query, prompt: "Песни, исполнители")
        .onSubmit(of: .search) { Task { await search() } }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        error = nil
        do {
            results = try await YouTubeService.search(text)
            if results.isEmpty { error = "Ничего не найдено" }
        } catch {
            self.error = "Ошибка поиска. Проверьте интернет."
        }
        isSearching = false
    }
}
