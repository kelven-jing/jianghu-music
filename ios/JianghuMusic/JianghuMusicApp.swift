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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @StateObject private var downloads = DownloadStore()

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

                                downloadButton(for: song)
                            }
                        }
                    }
                }
            }
            .navigationTitle("江湖音乐")
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

    private func formatSize(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}
