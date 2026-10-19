import Foundation
import CryptoKit

/// Ein Video des Kanals mit seiner aktuellen Leistung.
struct VideoInfo: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var publishedAt: Date?
    var thumbnailURL: URL?
    var views: Int
    var likes: Int
    var commentCount: Int

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
}

/// Ein einzelner Kommentar oder eine Antwort.
struct Comment: Identifiable, Codable, Hashable {
    let id: String
    let videoID: String
    /// nil bei Kommentaren der obersten Ebene, sonst der Kommentar, auf den geantwortet wird.
    let parentID: String?
    var authorName: String
    var authorChannelID: String?
    var authorChannelURL: String?
    var authorImageURL: URL?
    var text: String
    var likeCount: Int
    var publishedAt: Date
    var updatedAt: Date
    var replyCount: Int
    /// Die unveränderte Antwort der YouTube-API — für die Beweissicherung.
    var raw: Data

    var isEdited: Bool { updatedAt.timeIntervalSince(publishedAt) > 1 }

    /// Direkter Link: öffnet das Video mit diesem Kommentar hervorgehoben.
    var permalink: URL {
        var c = URLComponents(string: "https://www.youtube.com/watch")!
        c.queryItems = [URLQueryItem(name: "v", value: videoID), URLQueryItem(name: "lc", value: id)]
        return c.url!
    }

    /// Stabiler Fingerabdruck des Textes — ändert sich, wenn jemand bearbeitet.
    var textHash: String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Ein Kommentar mit seinen Antworten.
struct CommentThread: Identifiable, Hashable {
    var top: Comment
    var replies: [Comment]

    var id: String { top.id }
    var videoID: String { top.videoID }
    var all: [Comment] { [top] + replies }
    /// Die jüngste Aktivität im ganzen Strang — danach wird sortiert.
    var latest: Date { all.map(\.publishedAt).max() ?? top.publishedAt }
}

enum Mood: String, Codable, CaseIterable {
    case positive, neutral, negative

    var label: String {
        switch self {
        case .positive: return "positiv"
        case .neutral:  return "neutral"
        case .negative: return "negativ"
        }
    }
    var symbol: String {
        switch self {
        case .positive: return "hand.thumbsup.fill"
        case .neutral:  return "minus.circle.fill"
        case .negative: return "hand.thumbsdown.fill"
        }
    }
}

/// Einschätzung eines Kommentars.
struct Assessment: Codable, Hashable {
    var mood: Mood
    var score: Double?
    /// Nur KI: z. B. „Beleidigung“, „Drohung“, „Verhetzung“, „Spam“.
    var flag: String?
    var reason: String?
    var byAI: Bool
    /// Auf welche Fassung des Textes sich die Einschätzung bezieht.
    var textHash: String
}

/// Was von einem entfernten Kommentar in Erinnerung bleibt.
struct RemovedRecord: Codable, Hashable {
    var comment: Comment
    var removedAt: Date
    var bannedAuthor: Bool
    var evidenceFolder: String?
}
