import Foundation
import SwiftUI

enum DownloadError: LocalizedError {
    case invalidServerAddress
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidServerAddress:
            return "电脑服务器地址不正确。"
        case .unexpectedResponse:
            return "电脑服务没有正常提供歌曲文件。"
        }
    }
}

@MainActor
final class DownloadStore: ObservableObject {
    @Published private(set) var downloadingIDs: Set<String> = []
    @Published private(set) var completedDownloadCount = 0

    private let downloadsDirectory: URL = {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        return applicationSupport.appendingPathComponent(
            "DownloadedMusic",
            isDirectory: true
        )
    }()

    init() {
        try? FileManager.default.createDirectory(
            at: downloadsDirectory,
            withIntermediateDirectories: true
        )
    }

    func isDownloaded(_ song: Song) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: song).path)
    }

    func localURL(for song: Song) -> URL {
        downloadsDirectory
            .appendingPathComponent(fileName(for: song))
            .appendingPathExtension("mp3")
    }

    func download(_ song: Song, from serverAddress: String) async throws {
        guard !downloadingIDs.contains(song.id) else {
            return
        }

        guard let audioURL = audioURL(for: song, serverAddress: serverAddress) else {
            throw DownloadError.invalidServerAddress
        }

        downloadingIDs.insert(song.id)
        defer {
            downloadingIDs.remove(song.id)
        }

        let (temporaryURL, response) = try await URLSession.shared.download(from: audioURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 || httpResponse.statusCode == 206 else {
            throw DownloadError.unexpectedResponse
        }

        let destinationURL = localURL(for: song)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        completedDownloadCount += 1
    }

    func audioURL(for song: Song, serverAddress: String) -> URL? {
        apiURL(path: "/api/audio", song: song, serverAddress: serverAddress)
    }

    func lyricsURL(for song: Song, serverAddress: String) -> URL? {
        apiURL(path: "/api/lyrics", song: song, serverAddress: serverAddress)
    }

    private func apiURL(path: String, song: Song, serverAddress: String) -> URL? {
        let address = serverAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard var components = URLComponents(string: address + path) else {
            return nil
        }

        components.queryItems = [
            URLQueryItem(name: "id", value: song.id)
        ]

        return components.url
    }

    private func fileName(for song: Song) -> String {
        Data(song.id.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
