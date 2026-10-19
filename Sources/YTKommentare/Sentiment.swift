import Foundation
import NaturalLanguage

/// Stimmung eines Kommentars.
///
/// Lokal über das Sprachmodell von macOS: sofort, kostenlos, ohne Netz.
/// Im Test mit deutschen Kommentaren zuverlässig bei Lob, unzuverlässig bei
/// Fragen (oft „negativ“) und bei Anfeindungen (teils „positiv“). Fragen
/// werden deshalb auf neutral gestellt; für Anfeindungen gibt es die KI.
enum Sentiment {
    static func local(_ comment: Comment) -> Assessment {
        let text = comment.text
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        // Über alle Absätze mitteln — tag(at:) sähe nur den ersten.
        var scores: [Double] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .paragraph,
                             scheme: .sentimentScore, options: []) { tag, _ in
            if let value = tag.flatMap({ Double($0.rawValue) }) { scores.append(value) }
            return true
        }
        let score = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)

        var mood: Mood = score >= 0.3 ? .positive : (score <= -0.3 ? .negative : .neutral)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("?"), score > -0.8 { mood = .neutral }

        return Assessment(mood: mood, score: score, flag: nil, reason: nil,
                          byAI: false, textHash: comment.textHash)
    }
}

/// Optionale Einschätzung über OpenAI: genauere Stimmung und ein Hinweis auf
/// möglicherweise rechtlich relevante Inhalte. Nur ein Hinweis — keine Prüfung.
struct AIAssessor {
    let apiKey: String
    let model: String

    enum AIError: LocalizedError {
        case http(Int, String)
        case format
        var errorDescription: String? {
            switch self {
            case .http(let status, let message): return "KI-Einschätzung fehlgeschlagen (\(status)): \(message)"
            case .format: return "KI-Einschätzung: unerwartete Antwort."
            }
        }
    }

    private static let instructions = """
    Du bewertest YouTube-Kommentare unter Beiträgen eines österreichischen \
    Nachrichtenmagazins (ORF). Gib für jeden Kommentar zurück:
    - "mood": "positive" (Zustimmung, Lob, Dank), "neutral" (Fragen, Sachliches, \
      Anteilnahme ohne Angriff) oder "negative" (Ablehnung, Ärger, Angriff).
    - "flag": null, oder genau eines von "Beleidigung", "Drohung", "Verhetzung", \
      "Spam" — nur wenn der Kommentar klar in diese Richtung geht. Kritik am \
      Beitrag, an Politik oder am ORF ist KEIN Flag.
    - "reason": höchstens 8 Wörter, nur wenn flag gesetzt ist, sonst null.
    Antworte ausschließlich als JSON: {"results":[{"id":"…","mood":"…","flag":null,"reason":null}]}
    """

    func assess(_ comments: [Comment]) async throws -> [String: Assessment] {
        guard !comments.isEmpty else { return [:] }
        let items = comments.map { ["id": $0.id, "text": String($0.text.prefix(1500))] }
        let userContent = String(data: try JSONSerialization.data(withJSONObject: items), encoding: .utf8) ?? "[]"

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": Self.instructions],
                ["role": "user", "content": userContent],
            ],
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw AIError.http(http.statusCode, message)
        }
        guard let content = ((json?["choices"] as? [[String: Any]])?.first?["message"]
                                as? [String: Any])?["content"] as? String,
              let parsed = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [String: Any],
              let results = parsed["results"] as? [[String: Any]] else { throw AIError.format }

        let byID = Dictionary(comments.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [String: Assessment] = [:]
        for r in results {
            guard let id = r["id"] as? String, let comment = byID[id],
                  let mood = (r["mood"] as? String).flatMap(Mood.init(rawValue:)) else { continue }
            let flag = (r["flag"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            out[id] = Assessment(mood: mood, score: nil, flag: flag,
                                 reason: r["reason"] as? String, byAI: true,
                                 textHash: comment.textHash)
        }
        return out
    }
}
