import SwiftUI

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

    var body: some View {
        NavigationStack {
            Form {
                Section("局域网音乐库") {
                    TextField("电脑服务器地址", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    Button("连接并读取音乐") {
                        // 下一步会在这里读取电脑的歌曲列表。
                    }
                }

                Section("我的音乐") {
                    ContentUnavailableView(
                        "还没有同步歌曲",
                        systemImage: "music.note.list",
                        description: Text("连接家中 Wi-Fi 后，点“连接并读取音乐”。")
                    )
                }
            }
            .navigationTitle("江湖音乐")
        }
    }
}