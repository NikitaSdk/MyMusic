import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { SearchView().withMiniPlayer() }
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            NavigationStack { LibraryView().withMiniPlayer() }
                .tabItem { Label("Медиатека", systemImage: "music.note.house") }
            NavigationStack { PlaylistsView().withMiniPlayer() }
                .tabItem { Label("Плейлисты", systemImage: "music.note.list") }
        }
    }
}

extension View {
    /// Мини-плеер над панелью вкладок.
    func withMiniPlayer() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}
