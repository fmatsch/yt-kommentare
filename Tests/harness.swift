import SwiftUI
import AppKit

// Prüfstand: API-Antwort im Originalformat → Parser → Stimmung → Beweis → Bilder der Oberfläche.
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func comment(_ id: String, _ author: String, _ text: String, _ published: String,
             updated: String? = nil, likes: Int = 0, parent: String? = nil) -> [String: Any] {
    var s: [String: Any] = [
        "channelId": "UCWX19_CcEmdykXRQX3BjNQw", "videoId": "vidALS",
        "textDisplay": text, "textOriginal": text,
        "authorDisplayName": author, "authorProfileImageUrl": "https://example.invalid/a.jpg",
        "authorChannelUrl": "http://www.youtube.com/\(author)",
        "authorChannelId": ["value": "UC\(abs(author.hashValue) % 100000)"],
        "canRate": true, "viewerRating": "none", "likeCount": likes,
        "publishedAt": published, "updatedAt": updated ?? published,
    ]
    if let parent { s["parentId"] = parent }
    return ["kind": "youtube#comment", "id": id, "snippet": s]
}

let items: [[String: Any]] = [
    ["id": "T1", "snippet": ["videoId": "vidALS", "totalReplyCount": 1,
        "topLevelComment": comment("T1", "@maria_k", "Unfassbar, wie mit Schwerkranken umgegangen wird. Danke fürs Aufzeigen!", "2026-09-22T07:40:00Z", likes: 34)],
     "replies": ["comments": [comment("T1.r1", "@ORFKontext", "Danke! Wir bleiben an dem Fall dran.", "2026-09-22T09:05:00Z", likes: 5, parent: "T1")]]],
    ["id": "T2", "snippet": ["videoId": "vidALS", "totalReplyCount": 0,
        "topLevelComment": comment("T2", "@heinz1958", "Wann kommt der zweite Teil?", "2026-09-22T08:55:00Z")]],
    ["id": "T3", "snippet": ["videoId": "vidALS", "totalReplyCount": 0,
        "topLevelComment": comment("T3", "@wutbuerger77", "Die Politiker gehören alle eingesperrt, unfassbar diese Korruption! Ihr vom ORF seid keinen Deut besser.", "2026-09-22T08:20:00Z", updated: "2026-09-22T08:31:00Z", likes: 2)]],
    ["id": "T4", "snippet": ["videoId": "vidALS", "totalReplyCount": 0,
        "topLevelComment": comment("T4", "@gis_nein", "Lügenpresse. GIS abschaffen!", "2026-09-21T22:10:00Z")]],
]
let threads: [CommentThread] = items.compactMap { item in
    let snippet = item["snippet"] as! [String: Any]
    guard var top = YouTubeAPI.parse(snippet["topLevelComment"] as! [String: Any], videoID: "vidALS") else { return nil }
    top.replyCount = snippet["totalReplyCount"] as! Int
    let replies = ((item["replies"] as? [String: Any])?["comments"] as? [[String: Any]] ?? [])
        .compactMap { YouTubeAPI.parse($0, videoID: "vidALS") }
    return CommentThread(top: top, replies: replies)
}

print("== Parser ==")
for t in threads {
    for c in t.all {
        let a = Sentiment.local(c)
        print(String(format: "  %-8@ %5.2f  %@%@: %@", a.mood.label, a.score ?? 0, c.parentID == nil ? "" : "  ↳ ",
                     c.authorName, String(c.text.prefix(50))))
    }
}
print("  bearbeitet erkannt:", threads[2].top.isEdited, "· Direktlink:", threads[0].top.permalink.absoluteString)

MainActor.assumeIsolated {
    let auth = AuthManager()
    let store = CommentStore(auth: auth)
    let video = VideoInfo(id: "vidALS", title: "Einzelbett für ALS-Patient verweigert | Bürgeranwalt 19.09.2026",
                          publishedAt: YouTubeAPI.date("2026-09-19T16:34:00Z"), thumbnailURL: nil,
                          views: 18_432, likes: 612, commentCount: 87)
    store.loadSample(threads: threads, videos: [video], seen: ["T1", "T4"])

    // Beweissicherung mit einem echten Durchlauf
    let ctx = EvidenceContext(comment: threads[2].top, parent: nil, video: video,
                              channelTitle: "ORF Kontext", capturedAt: Date())
    do {
        let folder = try Evidence.save(ctx, into: out.appendingPathComponent("Beweise"))
        print("== Beweis ==")
        for f in (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted() ?? [] {
            let size = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(f).path)[.size] as? Int) ?? 0
            print("  \(f)  \(size) Bytes")
        }
        print("BEWEISORDNER=\(folder.path)")
    } catch { print("Beweis FEHLER: \(error)") }

    // Oberfläche als Bild: Kopf + Stränge, so wie im Fenster
    let page = VStack(alignment: .leading, spacing: 14) {
        VideoHeader(video: video, threads: store.threads)
        ForEach(store.threads) { ThreadView(thread: $0, showVideo: false) }
    }
    .padding(20)
    .frame(width: 900)
    .background(Color(nsColor: .windowBackgroundColor))
    .environmentObject(store)
    .environmentObject(auth)

    let renderer = ImageRenderer(content: page)
    renderer.scale = 1.5
    if let cg = renderer.cgImage,
       let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
        try? png.write(to: out.appendingPathComponent("oberflaeche.png"))
        print("OBERFLAECHE=\(out.appendingPathComponent("oberflaeche.png").path)")
    }
}
