import SwiftUI

struct Song: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let sizeBytes: Int
    let hasLyrics: Bool
}

struct LibraryResponse: Codable {
    let songs: [Song]
}

@main
struct JianghuMusicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @AppStorage("serverAddress")
    private var serverAddress = "http://10.201.30.6:8787"

    @State private var songs: [Song] = []
    @State private var lyricLines: [LyricLine] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var downloads = DownloadStore()
    @StateObject private var player = PlayerStore()

    var body: some View {
        NavigationStack {
            List {
                Section("局域网音乐库") {
                    TextField("电脑服务器地址", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Button {
                        loadLibrary()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Label("连接并读取音乐", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isLoading)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("我的音乐") {
                    if songs.isEmpty {
                        ContentUnavailableView(
                            "还没有同步歌曲",
                            systemImage: "music.note.list",
                            description: Text("连接家中 Wi-Fi 后，点“连接并读取音乐”。")
                        )
                    } else {
                        ForEach(songs) { song in
                            HStack(spacing: 12) {
                                Image(systemName: downloads.isDownloaded(song) ? "arrow.down.circle.fill" : "music.note")
                                    .foregroundStyle(downloads.isDownloaded(song) ? .green : .pink)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title)

                                    HStack(spacing: 5) {
                                        Text(formatSize(song.sizeBytes))

                                        if song.hasLyrics {
                                            Image(systemName: "text.quote")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 6) {
                                    Button("播放") {
                                        play(song)
                                    }
                                    .buttonStyle(.borderedProminent)

                                    downloadButton(for: song)
                                }
                            }
                        }
                    }
                }

                if player.currentSong != nil {
                    Section("同步歌词") {
                        if lyricLines.isEmpty {
                            Text("这首歌没有可用歌词，或电脑暂时未连接。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(lyricLines) { line in
                                Text(line.text)
                                    .fontWeight(isCurrentLyric(line) ? .bold : .regular)
                                    .foregroundStyle(isCurrentLyric(line) ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("江湖音乐")
            .safeAreaInset(edge: .bottom) {
                if let currentSong = player.currentSong {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundStyle(.pink)

                            Text(currentSong.title)
                                .lineLimit(1)

                            Spacer()

                            Button {
                                player.togglePlayback()
                            } label: {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if player.duration > 0 {
                            Slider(
                                value: Binding(
                                    get: { player.currentTime },
                                    set: { player.seek(to: $0) }
                                ),
                                in: 0...player.duration
                            )
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
    }

    private func loadLibrary() {
        let baseAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = baseAddress.hasSuffix("/") ? String(baseAddress.dropLast()) : baseAddress

        guard let url = URL(string: address + "/api/library") else {
            errorMessage = "电脑服务器地址不正确。"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            defer {
                isLoading = false
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    errorMessage = "电脑服务没有正常返回歌曲列表。"
                    return
                }

                let library = try JSONDecoder().decode(LibraryResponse.self, from: data)
                songs = library.songs
            } catch {
                errorMessage = "无法连接电脑。请确认手机和电脑在同一 Wi-Fi，且音乐服务正在运行。"
            }
        }
    }

    @ViewBuilder
    private func downloadButton(for song: Song) -> some View {
        if downloads.isDownloaded(song) {
            Text("已下载")
                .font(.caption)
                .foregroundStyle(.green)
        } else if downloads.downloadingIDs.contains(song.id) {
            ProgressView()
        } else {
            Button("下载") {
                download(song)
            }
            .buttonStyle(.bordered)
        }
    }

    private func download(_ song: Song) {
        errorMessage = nil

        Task {
            do {
                try await downloads.download(song, from: serverAddress)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func play(_ song: Song) {
        let sourceURL: URL?

        if downloads.isDownloaded(song) {
            sourceURL = downloads.localURL(for: song)
        } else {
            sourceURL = downloads.audioURL(for: song, serverAddress: serverAddress)
        }

        guard let sourceURL else {
            errorMessage = "电脑服务器地址不正确。"
            return
        }

        player.play(song: song, sourceURL: sourceURL)
        loadLyrics(for: song)
    }

    private func loadLyrics(for song: Song) {
        lyricLines = []

        guard let url = downloads.lyricsURL(for: song, serverAddress: serverAddress) else {
            return
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    return
                }

                let lyrics = try JSONDecoder().decode(LyricsResponse.self, from: data)
                guard lyrics.songId == song.id else {
                    return
                }

                lyricLines = lyrics.lines
            } catch {
                lyricLines = []
            }
        }
    }

    private func isCurrentLyric(_ line: LyricLine) -> Bool {
        guard let index = lyricLines.firstIndex(of: line) else {
            return false
        }

        let nextTime = lyricLines.indices.contains(index + 1)
            ? lyricLines[index + 1].timeMs
            : Int.max
        let currentTimeMs = Int(player.currentTime * 1000)

        return line.timeMs <= currentTimeMs && currentTimeMs < nextTime
    }

    private func formatSize(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
