import Foundation

struct LyricLine: Codable, Identifiable, Hashable {
    let timeMs: Int
    let text: String

    var id: Int {
        timeMs
    }
}

struct LyricsResponse: Codable {
    let songId: String
    let lines: [LyricLine]
}
