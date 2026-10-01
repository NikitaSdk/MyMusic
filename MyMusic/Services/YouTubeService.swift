import Foundation
import YouTubeKit

/// Поиск через внутренний API YouTube (InnerTube) и получение ссылки на аудиопоток.
enum YouTubeService {

    static func search(_ query: String) async throws -> [Song] {
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/search?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20250101.00.00",
                    "hl": "ru",
                    "gl": "UA"
                ]
            ],
            "query": query,
            "params": "EgIQAQ=="   // фильтр «только видео»
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let json = try JSONSerialization.jsonObject(with: data)

        var songs: [Song] = []
        var seen = Set<String>()
        collect(json) { song in
            if seen.insert(song.id).inserted { songs.append(song) }
        }
        return songs
    }

    /// Прямая ссылка на аудио (m4a), годная для AVPlayer. Живёт несколько часов.
    static func audioURL(for videoId: String) async throws -> URL {
        let streams = try await YouTube(videoID: videoId, methods: [.local, .remote]).streams
        let audio = streams.filterAudioOnly()
        if let best = audio.filter({ $0.fileExtension == .m4a }).highestAudioBitrateStream() {
            return best.url
        }
        if let any = audio.filter({ $0.isNativelyPlayable }).highestAudioBitrateStream() {
            return any.url
        }
        throw URLError(.resourceUnavailable)
    }

    // MARK: - Разбор ответа

    private static func collect(_ node: Any, _ found: (Song) -> Void) {
        if let dict = node as? [String: Any] {
            if let renderer = dict["videoRenderer"] as? [String: Any] {
                if let song = parse(renderer) { found(song) }
                return
            }
            for value in dict.values { collect(value, found) }
        } else if let array = node as? [Any] {
            for item in array { collect(item, found) }
        }
    }

    private static func parse(_ v: [String: Any]) -> Song? {
        guard let id = v["videoId"] as? String else { return nil }
        let duration = text(v["lengthText"]) ?? ""
        guard !duration.isEmpty else { return nil }        // пропускаем прямые эфиры
        return Song(
            id: id,
            title: text(v["title"]) ?? "Без названия",
            artist: text(v["ownerText"]) ?? text(v["longBylineText"]) ?? "",
            duration: duration,
            thumbnailURL: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg"
        )
    }

    private static func text(_ node: Any?) -> String? {
        guard let dict = node as? [String: Any] else { return nil }
        if let simple = dict["simpleText"] as? String { return simple }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return nil
    }
}
