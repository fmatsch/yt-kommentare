import SwiftUI
import AppKit

// MARK: - Liste: ein Video oder alle

enum CommentFilter: String, CaseIterable, Identifiable {
    case all = "Alle", new = "Neu", negative = "Negativ", flagged = "Mit Hinweis", archived = "Gesichert"
    var id: String { rawValue }
}

struct CommentListView: View {
    /// nil = alle Videos
    let videoID: String?
    @EnvironmentObject var store: CommentStore
    @State private var filter: CommentFilter = .all
    @State private var search = ""

    private var threads: [CommentThread] {
        let base = store.threads(for: videoID)
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return base.compactMap { thread in
            let matching = thread.all.filter { matches($0, query) }
            // Ein Strang bleibt, wenn irgendein Kommentar darin passt.
            return matching.isEmpty ? nil : thread
        }
    }

    private func matches(_ c: Comment, _ query: String) -> Bool {
        if !query.isEmpty, !c.text.lowercased().contains(query), !c.authorName.lowercased().contains(query) {
            return false
        }
        switch filter {
        case .all:      return true
        case .new:      return store.isNew(c)
        case .negative: return store.assessment(for: c)?.mood == .negative
        case .flagged:  return store.assessment(for: c)?.flag != nil
        case .archived: return store.archived[c.id] != nil
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: []) {
                if let videoID, let video = store.videos[videoID] {
                    VideoHeader(video: video, threads: store.threads(for: videoID))
                } else {
                    AllHeader(threads: store.threads)
                }

                HStack(spacing: 10) {
                    Picker("Filter", selection: $filter) {
                        ForEach(CommentFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    TextField("Suchen in Text oder Name", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Spacer()
                    Text("\(threads.count) Stränge").font(.caption).foregroundStyle(.secondary)
                }

                if threads.isEmpty {
                    Text(store.threads.isEmpty ? "Noch keine Kommentare geladen." : "Keine Kommentare für diesen Filter.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 30)
                        .frame(maxWidth: .infinity)
                }

                ForEach(threads) { thread in
                    ThreadView(thread: thread, showVideo: videoID == nil)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Köpfe

struct VideoHeader: View {
    let video: VideoInfo
    let threads: [CommentThread]
    @EnvironmentObject var store: CommentStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: { Color.secondary.opacity(0.15) }
            .frame(width: 192, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 8) {
                Text(video.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                if let date = video.publishedAt {
                    Text("Veröffentlicht \(Format.full(date))").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 22) {
                    Stat(label: "Aufrufe", value: video.views.formatted())
                    Stat(label: "Likes", value: video.likes.formatted())
                    Stat(label: "Kommentare", value: video.commentCount.formatted())
                    Link(destination: video.url) {
                        Label("Auf YouTube", systemImage: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                MoodSummary(counts: store.moodCounts(threads), flagged: store.flaggedCount(threads))
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.15)))
    }
}

struct AllHeader: View {
    let threads: [CommentThread]
    @EnvironmentObject var store: CommentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alle Kommentare").font(.title2.weight(.semibold))
            Text("Über alle Videos, neuester zuerst · \(store.videos.count) Videos mit Kommentaren")
                .font(.callout).foregroundStyle(.secondary)
            MoodSummary(counts: store.moodCounts(threads), flagged: store.flaggedCount(threads))
        }
    }
}

struct Stat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Stimmung

enum MoodColor {
    static func color(_ mood: Mood) -> Color {
        switch mood {
        case .positive: return Color(red: 0.05, green: 0.64, blue: 0.05)
        case .neutral:  return Color.secondary.opacity(0.45)
        case .negative: return Color(red: 0.82, green: 0.23, blue: 0.23)
        }
    }
}

struct MoodBar: View {
    let counts: [Mood: Int]

    var body: some View {
        let total = max(1, counts.values.reduce(0, +))
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    let n = counts[mood, default: 0]
                    if n > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(MoodColor.color(mood))
                            .frame(width: max(3, (geo.size.width - 4) * CGFloat(n) / CGFloat(total)))
                    }
                }
            }
        }
    }
}

struct MoodSummary: View {
    let counts: [Mood: Int]
    let flagged: Int

    var body: some View {
        let total = counts.values.reduce(0, +)
        VStack(alignment: .leading, spacing: 5) {
            MoodBar(counts: counts).frame(height: 8).frame(maxWidth: 420)
            HStack(spacing: 14) {
                ForEach(Mood.allCases, id: \.self) { mood in
                    let n = counts[mood, default: 0]
                    Label("\(n) \(mood.label)\(total > 0 ? " (\(Int((Double(n) / Double(total) * 100).rounded())) %)" : "")",
                          systemImage: mood.symbol)
                        .foregroundStyle(MoodColor.color(mood))
                        .font(.caption)
                }
                if flagged > 0 {
                    Label("\(flagged) mit Hinweis", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.caption)
                }
            }
        }
    }
}

// MARK: - Strang und Kommentar

struct ThreadView: View {
    let thread: CommentThread
    let showVideo: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentRow(comment: thread.top, showVideo: showVideo)
            if !thread.replies.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(thread.replies) { reply in
                        CommentRow(comment: reply, showVideo: false)
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct CommentRow: View {
    let comment: Comment
    let showVideo: Bool
    @EnvironmentObject var store: CommentStore
    @State private var confirmingRemoval = false

    var body: some View {
        let assessment = store.assessment(for: comment)
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: comment.authorImageURL) { image in
                image.resizable()
            } placeholder: {
                Circle().fill(Color.secondary.opacity(0.2))
                    .overlay(Text(String(comment.authorName.prefix(1))).font(.caption.weight(.semibold)))
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(comment.authorName).font(.callout.weight(.semibold))
                    Text(Format.relative(comment.publishedAt))
                        .font(.caption).foregroundStyle(.secondary)
                        .help(Format.full(comment.publishedAt))
                    if comment.isEdited {
                        Text("bearbeitet").font(.caption).foregroundStyle(.secondary)
                            .help("Zuletzt bearbeitet \(Format.full(comment.updatedAt))")
                    }
                    if store.isNew(comment) {
                        Text("neu").font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor)).foregroundStyle(.white)
                    }
                    Spacer()
                    if let assessment { MoodBadge(assessment: assessment) }
                }

                if showVideo, let video = store.videos[comment.videoID] {
                    Label(video.title, systemImage: "play.rectangle")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }

                Text(comment.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let flag = assessment?.flag {
                    Label("Hinweis: \(flag)\(assessment?.reason.map { " — \($0)" } ?? "")",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }

                HStack(spacing: 14) {
                    if comment.likeCount > 0 {
                        Label("\(comment.likeCount)", systemImage: "hand.thumbsup").font(.caption).foregroundStyle(.secondary)
                    }
                    if comment.parentID == nil, comment.replyCount > 0 {
                        Label("\(comment.replyCount)", systemImage: "arrowshape.turn.up.left").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let folder = store.archived[comment.id] {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                        } label: { Label("Gesichert", systemImage: "checkmark.seal.fill") }
                        .foregroundStyle(.green)
                        .help(folder)
                    } else {
                        Button { store.archive(comment) } label: {
                            Label("Sichern", systemImage: "square.and.arrow.down")
                        }
                        .help("Als Beweis sichern: PDF, Bild, Rohdaten und Prüfsummen")
                    }
                    Button(role: .destructive) { confirmingRemoval = true } label: {
                        Label("Entfernen…", systemImage: "trash")
                    }
                    Link(destination: comment.permalink) {
                        Label("Auf YouTube", systemImage: "arrow.up.right.square")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .contextMenu {
            Button("Text kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(comment.text, forType: .string)
            }
            Button("Link kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(comment.permalink.absoluteString, forType: .string)
            }
        }
        .sheet(isPresented: $confirmingRemoval) {
            RemoveSheet(comment: comment).environmentObject(store)
        }
    }
}

struct MoodBadge: View {
    let assessment: Assessment
    var body: some View {
        Label(assessment.mood.label, systemImage: assessment.mood.symbol)
            .font(.caption)
            .foregroundStyle(MoodColor.color(assessment.mood))
            .help(assessment.byAI ? "Einschätzung: KI" : "Einschätzung: macOS-Sprachanalyse\(assessment.score.map { String(format: " (%.1f)", $0) } ?? "")")
    }
}

// MARK: - Entfernen

struct RemoveSheet: View {
    let comment: Comment
    @EnvironmentObject var store: CommentStore
    @Environment(\.dismiss) private var dismiss
    @State private var archiveFirst = true
    @State private var banAuthor = false
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Kommentar entfernen").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.authorName).font(.callout.weight(.semibold))
                Text(comment.text).font(.callout).lineLimit(6)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))

            Text("Der Kommentar wird auf YouTube ausgeblendet — wie „Entfernen“ in YouTube Studio. Ob sich das später rückgängig machen lässt, ist nicht garantiert.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Vorher als Beweis sichern", isOn: $archiveFirst)
                .disabled(store.archived[comment.id] != nil)
            if store.archived[comment.id] != nil {
                Text("Ist bereits gesichert.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Verfasser:in auf dem Kanal sperren", isOn: $banAuthor)
            if banAuthor {
                Text("Weitere Kommentare dieser Person werden dann automatisch ausgeblendet.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    working = true
                    Task {
                        let ok = await store.remove(comment, banAuthor: banAuthor, archiveFirst: archiveFirst)
                        working = false
                        if ok { dismiss() }
                    }
                } label: {
                    if working { ProgressView().controlSize(.small) } else { Text("Entfernen") }
                }
                .disabled(working)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

// MARK: - Entfernt

struct RemovedListView: View {
    @EnvironmentObject var store: CommentStore

    var body: some View {
        let records = store.removed.values.sorted { $0.removedAt > $1.removedAt }
        List(records, id: \.comment.id) { record in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.comment.authorName).font(.callout.weight(.semibold))
                    Text("entfernt \(Format.full(record.removedAt))").font(.caption).foregroundStyle(.secondary)
                    if record.bannedAuthor {
                        Text("gesperrt").font(.caption2.weight(.semibold)).foregroundStyle(.red)
                    }
                    Spacer()
                    if let folder = record.evidenceFolder {
                        Button("Beweis zeigen") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                        }
                        .buttonStyle(.link).font(.caption)
                    }
                }
                if let video = store.videos[record.comment.videoID] {
                    Text(video.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(record.comment.text).font(.callout).textSelection(.enabled)
            }
            .padding(.vertical, 4)
        }
    }
}
