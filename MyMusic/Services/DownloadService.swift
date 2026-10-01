import Foundation
import Observation

/// Скачивание треков для прослушивания без интернета.
@MainActor
@Observable
final class DownloadService {
    static let shared = DownloadService()

    private(set) var downloaded: Set<String> = []
    private(set) var inProgress: Set<String> = []

    private init() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        downloaded = Set(files.filter { $0.hasSuffix(".m4a") }.map { String($0.dropLast(4)) })
    }

    // MARK: - Пути к файлам

    nonisolated static var folder: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    nonisolated static func fileURL(for id: String) -> URL { folder.appendingPathComponent("\(id).m4a") }
    nonisolated static func thumbURL(for id: String) -> URL { folder.appendingPathComponent("\(id).jpg") }

    nonisolated static func localURL(for id: String) -> URL? {
        let url = fileURL(for: id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ id: String) -> Bool { downloaded.contains(id) }

    // MARK: - Действия

    func download(_ song: Song) async throws {
        guard !inProgress.contains(song.id), !downloaded.contains(song.id) else { return }
        inProgress.insert(song.id)
        defer { inProgress.remove(song.id) }

        let remote = try await YouTubeService.audioURL(for: song.id)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try await Self.chunkedDownload(from: remote, to: temp)

        let destination = Self.fileURL(for: song.id)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)

        // Обложка — чтобы она была видна и без интернета
        if let thumb = URL(string: song.thumbnailURL),
           let result = try? await URLSession.shared.data(from: thumb) {
            try? result.0.write(to: Self.thumbURL(for: song.id))
        }
        downloaded.insert(song.id)
    }

    func remove(_ id: String) {
        try? FileManager.default.removeItem(at: Self.fileURL(for: id))
        try? FileManager.default.removeItem(at: Self.thumbURL(for: id))
        downloaded.remove(id)
    }

    /// YouTube отдаёт файлы кусками быстрее, чем одним запросом, поэтому качаем по 4 МБ.
    nonisolated private static func chunkedDownload(from url: URL, to destination: URL) async throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let chunkSize = 4 * 1024 * 1024
        var start = 0
        while true {
            var request = URLRequest(url: url)
            request.setValue("bytes=\(start)-\(start + chunkSize - 1)", forHTTPHeaderField: "Range")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try handle.write(contentsOf: data)
            start += data.count

            if http.statusCode == 200 || data.count < chunkSize { break }
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let total = Int(range.split(separator: "/").last ?? ""),
               start >= total { break }
        }
    }
}
