import Foundation
import SwiftData

/// Лёгкая модель трека для поиска, очереди и плеера.
struct Song: Identifiable, Hashable, Codable {
    let id: String          // videoId на YouTube
    var title: String
    var artist: String
    var duration: String
    var thumbnailURL: String
}

/// Трек, сохранённый в медиатеке (хранится в SwiftData).
@Model
final class Track {
    @Attribute(.unique) var videoId: String
    var title: String
    var artist: String
    var duration: String
    var thumbnailURL: String
    var isSaved: Bool
    var addedAt: Date

    init(song: Song, isSaved: Bool = false) {
        videoId = song.id
        title = song.title
        artist = song.artist
        duration = song.duration
        thumbnailURL = song.thumbnailURL
        self.isSaved = isSaved
        addedAt = .now
    }

    var song: Song {
        Song(id: videoId, title: title, artist: artist, duration: duration, thumbnailURL: thumbnailURL)
    }
}

/// Плейлист: упорядоченный список videoId.
@Model
final class Playlist {
    var name: String
    var createdAt: Date
    var trackIds: [String]

    init(name: String) {
        self.name = name
        createdAt = .now
        trackIds = []
    }
}

/// Операции над медиатекой.
@MainActor
enum Library {
    static func track(for song: Song, in context: ModelContext) -> Track {
        let id = song.id
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.videoId == id })
        if let existing = try? context.fetch(descriptor).first { return existing }
        let track = Track(song: song)
        context.insert(track)
        return track
    }

    static func isSaved(_ song: Song, in context: ModelContext) -> Bool {
        let id = song.id
        let descriptor = FetchDescriptor<Track>(predicate: #Predicate { $0.videoId == id && $0.isSaved == true })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    static func setSaved(_ song: Song, _ saved: Bool, in context: ModelContext) {
        let track = track(for: song, in: context)
        track.isSaved = saved
        if saved { track.addedAt = .now }
        try? context.save()
    }

    static func add(_ song: Song, to playlist: Playlist, in context: ModelContext) {
        _ = track(for: song, in: context)
        if !playlist.trackIds.contains(song.id) {
            playlist.trackIds.append(song.id)
        }
        try? context.save()
    }
}
