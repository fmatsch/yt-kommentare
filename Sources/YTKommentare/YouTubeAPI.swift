import Foundation

enum APIError: LocalizedError {
    case http(Int, String)
    case scope

    var errorDescription: String? {
        switch self {
        case .scope:
            return "Diese Anmeldung darf keine Kommentare lesen oder moderieren. Bitte in den Einstellungen neu anmelden."
        case .http(let status, let message):
            return "YouTube meldet \(status): \(message)"
        }
    }
}

/// Die paar Aufrufe der YouTube Data API, die die App braucht.
/// Kosten je Aufruf: Lesen 1 Einheit, Moderieren 50 Einheiten.
enum YouTubeAPI {
    private static let base = "https://www.googleapis.com/youtube/v3"

    // MARK: - Lesen

    /// Neueste Kommentarstränge über alle Videos des Kanals.
    static func threads(channelID: String, pages: Int, token: String) async throws -> [CommentThread] {
        var result: [CommentThread] = []
        var pageToken: String?
        for _ in 0..<pages {
            var query = ["part": "snippet,replies", "allThreadsRelatedToChannelId": channelID,
                         "order": "time", "maxResults": "100", "textFormat": "plainText"]
            if let pageToken { query["pageToken"] = pageToken }
            let json = try await get("commentThreads", query, token: token)
            for item in json["items"] as? [[String: Any]] ?? [] {
                guard let snippet = item["snippet"] as? [String: Any],
                      let videoID = snippet["videoId"] as? String,
                      let topRaw = snippet["topLevelComment"] as? [String: Any],
                      var top = parse(topRaw, videoID: videoID) else { continue }
                top.replyCount = snippet["totalReplyCount"] as? Int ?? 0
                let replies = ((item["replies"] as? [String: Any])?["comments"] as? [[String: Any]] ?? [])
                    .compactMap { parse($0, videoID: videoID) }
                result.append(CommentThread(top: top, replies: replies))
            }
            pageToken = json["nextPageToken"] as? String
            if pageToken == nil { break }
        }
        return result
    }

    /// Alle Antworten auf einen Kommentar (die Stränge liefern nur einen Teil mit).
    static func replies(parentID: String, videoID: String, token: String) async throws -> [Comment] {
        var result: [Comment] = []
        var pageToken: String?
        repeat {
            var query = ["part": "snippet", "parentId": parentID, "maxResults": "100", "textFormat": "plainText"]
            if let pageToken { query["pageToken"] = pageToken }
            let json = try await get("comments", query, token: token)
            result += (json["items"] as? [[String: Any]] ?? []).compactMap { parse($0, videoID: videoID) }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil
        return result
    }

    static func videos(ids: [String], token: String) async throws -> [VideoInfo] {
        var result: [VideoInfo] = []
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = ids[start..<min(start + 50, ids.count)]
            let json = try await get("videos", ["part": "snippet,statistics",
                                                "id": batch.joined(separator: ","),
                                                "maxResults": "50"], token: token)
            for item in json["items"] as? [[String: Any]] ?? [] {
                guard let id = item["id"] as? String,
                      let snippet = item["snippet"] as? [String: Any] else { continue }
                let stats = item["statistics"] as? [String: Any] ?? [:]
                let thumbs = snippet["thumbnails"] as? [String: Any] ?? [:]
                let thumb = ((thumbs["medium"] ?? thumbs["default"]) as? [String: Any])?["url"] as? String
                result.append(VideoInfo(
                    id: id,
                    title: snippet["title"] as? String ?? id,
                    publishedAt: (snippet["publishedAt"] as? String).flatMap(date),
                    thumbnailURL: thumb.flatMap(URL.init(string:)),
                    views: Int(stats["viewCount"] as? String ?? "") ?? 0,
                    likes: Int(stats["likeCount"] as? String ?? "") ?? 0,
                    commentCount: Int(stats["commentCount"] as? String ?? "") ?? 0))
            }
        }
        return result
    }

    // MARK: - Moderieren

    /// Blendet einen fremden Kommentar aus — wie „Entfernen“ in YouTube Studio.
    /// comments.delete ginge nur bei eigenen Kommentaren; für die anderer ist
    /// setModerationStatus = rejected der vorgesehene Weg.
    static func reject(commentID: String, banAuthor: Bool, token: String) async throws {
        var comps = URLComponents(string: "\(base)/comments/setModerationStatus")!
        comps.queryItems = [URLQueryItem(name: "id", value: commentID),
                            URLQueryItem(name: "moderationStatus", value: "rejected"),
                            URLQueryItem(name: "banAuthor", value: banAuthor ? "true" : "false")]
        var request = URLRequest(url: comps.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
    }

    // MARK: - Intern

    private static func get(_ endpoint: String, _ query: [String: String], token: String) async throws -> [String: Any] {
        var comps = URLComponents(string: "\(base)/\(endpoint)")!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let error = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? [String: Any]
        let reason = (error?["errors"] as? [[String: Any]])?.first?["reason"] as? String
        if reason == "insufficientPermissions" { throw APIError.scope }
        throw APIError.http(http.statusCode, error?["message"] as? String ?? "")
    }

    /// Kommentar-Ressource → Comment, samt unveränderter Rohdaten.
    static func parse(_ resource: [String: Any], videoID: String) -> Comment? {
        guard let id = resource["id"] as? String,
              let s = resource["snippet"] as? [String: Any],
              let published = (s["publishedAt"] as? String).flatMap(date) else { return nil }
        let raw = (try? JSONSerialization.data(withJSONObject: resource,
                                               options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return Comment(
            id: id,
            videoID: s["videoId"] as? String ?? videoID,
            parentID: s["parentId"] as? String,
            authorName: s["authorDisplayName"] as? String ?? "Unbekannt",
            authorChannelID: (s["authorChannelId"] as? [String: Any])?["value"] as? String,
            authorChannelURL: s["authorChannelUrl"] as? String,
            authorImageURL: (s["authorProfileImageUrl"] as? String).flatMap(URL.init(string:)),
            text: (s["textOriginal"] as? String) ?? (s["textDisplay"] as? String) ?? "",
            likeCount: s["likeCount"] as? Int ?? 0,
            publishedAt: published,
            updatedAt: (s["updatedAt"] as? String).flatMap(date) ?? published,
            replyCount: 0,
            raw: raw)
    }

    static func date(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string)
    }
}
