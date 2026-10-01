import SwiftUI
import SwiftData

@main
struct MyMusicApp: App {
    @State private var player = PlayerService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
        }
        .modelContainer(for: [Track.self, Playlist.self])
    }
}
