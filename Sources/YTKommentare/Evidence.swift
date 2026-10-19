import SwiftUI
import AppKit
import CryptoKit

/// Alles, was zu einem gesicherten Kommentar gehört.
struct EvidenceContext {
    var comment: Comment
    var parent: Comment?
    var video: VideoInfo?
    var channelTitle: String
    var capturedAt: Date
}

/// Beweissicherung: pro Kommentar ein Ordner mit
///   Beweis.pdf / Beweis.png — alle Angaben lesbar aufbereitet
///   kommentar.json          — unveränderte Rohdaten der YouTube-API
///   pruefsummen.txt         — SHA-256 aller Dateien
/// Die Prüfsummen zeigen später, dass seit der Sicherung nichts verändert wurde.
enum Evidence {
    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YT-Kommentare Beweise", isDirectory: true)
    }

    static let localTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_AT")
        f.timeZone = TimeZone(identifier: "Europe/Vienna")
        f.dateFormat = "dd.MM.yyyy, HH:mm:ss zzz"
        return f
    }()

    @MainActor
    static func save(_ ctx: EvidenceContext, into base: URL) throws -> URL {
        let fm = FileManager.default
        let stamp: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "de_AT")
            f.timeZone = TimeZone(identifier: "Europe/Vienna")
            f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            return f.string(from: ctx.capturedAt)
        }()
        let name = sanitize("\(stamp) – \(ctx.comment.authorName) – \(ctx.video?.title ?? ctx.comment.videoID)")
        let folder = base.appendingPathComponent(String(name.prefix(120)), isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // 1) Rohdaten
        let json = folder.appendingPathComponent("kommentar.json")
        try rawDocument(ctx).write(to: json, options: .atomic)

        // 2) Lesbare Fassung als PDF und Bild
        let card = EvidenceCard(ctx: ctx)
            .frame(width: 720)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: 720, height: nil)

        let pdf = folder.appendingPathComponent("Beweis.pdf")
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(pdf as CFURL, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }

        renderer.scale = 2
        let png = folder.appendingPathComponent("Beweis.png")
        if let image = renderer.cgImage,
           let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try data.write(to: png, options: .atomic)
        }

        // 3) Prüfsummen
        var lines = ["Prüfsummen (SHA-256) der Beweissicherung",
                     "Erstellt: \(localTime.string(from: ctx.capturedAt))",
                     ""]
        for file in [pdf, png, json] where fm.fileExists(atPath: file.path) {
            let digest = SHA256.hash(data: try Data(contentsOf: file))
            lines.append("\(digest.map { String(format: "%02x", $0) }.joined())  \(file.lastPathComponent)")
        }
        lines += ["", "Prüfen im Terminal:  shasum -a 256 Beweis.pdf Beweis.png kommentar.json"]
        try lines.joined(separator: "\n").appending("\n")
            .write(to: folder.appendingPathComponent("pruefsummen.txt"), atomically: true, encoding: .utf8)

        return folder
    }

    private static func rawDocument(_ ctx: EvidenceContext) throws -> Data {
        func object(_ data: Data?) -> Any {
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
            return obj
        }
        let iso = ISO8601DateFormatter()
        let document: [String: Any] = [
            "beweissicherung": [
                "gesichert_am_utc": iso.string(from: ctx.capturedAt),
                "gesichert_am_lokal": localTime.string(from: ctx.capturedAt),
                "werkzeug": "YT Kommentare 1.0 (YouTube Data API v3)",
                "rechner": Host.current().localizedName ?? "",
            ],
            "kanal": ctx.channelTitle,
            "video": [
                "id": ctx.comment.videoID,
                "titel": ctx.video?.title ?? "",
                "url": "https://www.youtube.com/watch?v=\(ctx.comment.videoID)",
            ],
            "kommentar_link": ctx.comment.permalink.absoluteString,
            "kommentar": object(ctx.comment.raw),
            "antwort_auf": object(ctx.parent?.raw),
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    private static func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        return s.components(separatedBy: bad).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}

/// Die lesbare Fassung — bewusst schlicht und druckfreundlich.
struct EvidenceCard: View {
    let ctx: EvidenceContext
    private var c: Comment { ctx.comment }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Beweissicherung · YouTube-Kommentar")
                    .font(.system(size: 20, weight: .semibold))
                Text("Gesichert am \(Evidence.localTime.string(from: ctx.capturedAt))")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            section("Video") {
                row("Titel", ctx.video?.title ?? "–")
                row("Adresse", "https://www.youtube.com/watch?v=\(c.videoID)")
                row("Kanal", ctx.channelTitle)
            }

            section("Verfasser:in") {
                row("Anzeigename", c.authorName)
                row("Kanal-Adresse", c.authorChannelURL ?? "–")
                row("Kanal-ID", c.authorChannelID ?? "–")
            }

            section("Kommentar") {
                row("Veröffentlicht", Evidence.localTime.string(from: c.publishedAt))
                if c.isEdited { row("Zuletzt bearbeitet", Evidence.localTime.string(from: c.updatedAt)) }
                row("Likes", "\(c.likeCount)")
                row("Kommentar-ID", c.id)
                row("Direktlink", c.permalink.absoluteString)
            }

            if let parent = ctx.parent {
                section("Antwort auf") {
                    row("Verfasser:in", parent.authorName)
                    Text(parent.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("WORTLAUT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Text(c.text)
                    .font(.system(size: 15))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.955)))
            }

            Text("Erstellt mit YT Kommentare über die YouTube Data API v3. Die unveränderten Rohdaten (kommentar.json) und die Prüfsummen (pruefsummen.txt) liegen im selben Ordner.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(32)
        .foregroundStyle(Color.black)
        .background(Color.white)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
