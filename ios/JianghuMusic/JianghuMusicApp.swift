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
                            HStack {
                                Image(systemName: "music.note")
                                    .foregroundStyle(.pink)

                                VStack(alignment: .leading) {
                                    Text(song.title)

                                    Text(formatSize(song.sizeBytes))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if song.hasLyrics {
                                    Image(systemName: "text.quote")
                                        .foregroundStyle(.secondary)
                                }
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

    private func formatSize(_ bytes: Int) -> String {
        String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}