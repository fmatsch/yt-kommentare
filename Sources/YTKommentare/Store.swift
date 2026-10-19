import Foundation
import SwiftUI
import UserNotifications

/// Hält Kommentare, Videos und Einschätzungen, fragt regelmäßig neu ab und
/// merkt sich Gelesenes, Gesichertes und Entferntes über Neustarts hinweg.
@MainActor
final class CommentStore: ObservableObject {
    @Published private(set) var threads: [CommentThread] = []
    @Published private(set) var videos: [String: VideoInfo] = [:]
    @Published private(set) var assessments: [String: Assessment] = [:]
    @Published private(set) var seen: Set<String> = []
    @Published private(set) var archived: [String: String] = [:]
    @Published private(set) var removed: [String: RemovedRecord] = [:]
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published var errorMessage: String?
    @Published var status: String = ""

    // Einstellungen
    @Published var intervalMinutes: Int {
        didSet { UserDefaults.standard.set(intervalMinutes, forKey: "intervalMinutes"); restartTimer() }
    }
    @Published var notify: Bool {
        didSet { UserDefaults.standard.set(notify, forKey: "notify"); if notify { requestNotifications() } }
    }
    @Published var evidenceFolder: String {
        didSet { UserDefaults.standard.set(evidenceFolder, forKey: "evidenceFolder") }
    }
    @Published var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: "aiEnabled") }
    }
    @Published var aiModel: String {
        didSet { UserDefaults.standard.set(aiModel, forKey: "aiModel") }
    }
    @Published var aiKey: String {
        didSet { Keychain.setString(aiKey, "openai_key") }
    }

    let auth: AuthManager
    private var timer: Timer?
    private var knownIDs: Set<String> = []
    private var firstLoadThisSession = true
    private let fileURL: URL

    /// Wie viele Seiten à 100 Kommentarstränge pro Abruf (je 1 Einheit).
    private let pages = 2
    /// Höchstens so viele Stränge pro Abruf vollständig nachladen.
    private let replyBudget = 20

    init(auth: AuthManager) {
        self.auth = auth
        let d = UserDefaults.standard
        intervalMinutes = d.object(forKey: "intervalMinutes") as? Int ?? 10
        notify = d.object(forKey: "notify") as? Bool ?? true
        evidenceFolder = d.string(forKey: "evidenceFolder") ?? Evidence.defaultFolder.path
        aiEnabled = d.bool(forKey: "aiEnabled")
        aiModel = d.string(forKey: "aiModel") ?? "gpt-5-mini"
        aiKey = Keychain.string("openai_key") ?? ""

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YT Kommentare", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("zustand.json")
        load()
    }

    // MARK: - Abgeleitet

    /// Videos, sortiert nach dem jüngsten Kommentar.
    var videoOrder: [VideoInfo] {
        var latest: [String: Date] = [:]
        for t in threads { latest[t.videoID] = max(latest[t.videoID] ?? .distantPast, t.latest) }
        return latest.sorted { $0.value > $1.value }.compactMap { videos[$0.key] }
    }

    func threads(for videoID: String?) -> [CommentThread] {
        guard let videoID else { return threads }
        return threads.filter { $0.videoID == videoID }
    }

    func latest(videoID: String) -> Date? {
        threads(for: videoID).map(\.latest).max()
    }

    func assessment(for comment: Comment) -> Assessment? {
        guard let a = assessments[comment.id], a.textHash == comment.textHash else { return nil }
        return a
    }

    func moodCounts(_ threads: [CommentThread]) -> [Mood: Int] {
        var counts: [Mood: Int] = [:]
        for c in threads.flatMap(\.all) { counts[assessment(for: c)?.mood ?? .neutral, default: 0] += 1 }
        return counts
    }

    func flaggedCount(_ threads: [CommentThread]) -> Int {
        threads.flatMap(\.all).filter { assessment(for: $0)?.flag != nil }.count
    }

    func isNew(_ comment: Comment) -> Bool { !seen.contains(comment.id) }

    func unseenCount(videoID: String?) -> Int {
        threads(for: videoID).flatMap(\.all).filter { isNew($0) }.count
    }

    func parent(of comment: Comment) -> Comment? {
        guard let pid = comment.parentID else { return nil }
        return threads.first { $0.top.id == pid }?.top
    }

    // MARK: - Abruf

    func startMonitoring() {
        restartTimer()
        Task { await refresh() }
        if notify { requestNotifications() }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(max(1, intervalMinutes) * 60),
                                     repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard auth.isSignedIn, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        status = "Kommentare werden abgerufen …"

        do {
            let token = try await auth.validAccessToken()
            if auth.channelID == nil { await auth.fetchChannelName() }
            guard let channelID = auth.channelID else {
                throw APIError.http(0, "Zu dieser Anmeldung wurde kein YouTube-Kanal gefunden.")
            }

            var fetched = try await YouTubeAPI.threads(channelID: channelID, pages: pages, token: token)

            // Stränge mit mehr Antworten, als mitgeliefert wurden, vollständig holen.
            var budget = replyBudget
            for i in fetched.indices
            where fetched[i].top.replyCount > fetched[i].replies.count && budget > 0 {
                budget -= 1
                fetched[i].replies = try await YouTubeAPI.replies(
                    parentID: fetched[i].top.id, videoID: fetched[i].videoID, token: token)
            }

            // Was wir entfernt haben, kann YouTube noch kurz ausliefern.
            fetched = fetched.compactMap { thread in
                guard removed[thread.top.id] == nil else { return nil }
                var t = thread
                t.replies.removeAll { removed[$0.id] != nil }
                t.replies.sort { $0.publishedAt > $1.publishedAt }
                return t
            }
            fetched.sort { $0.latest > $1.latest }

            let infos = try await YouTubeAPI.videos(ids: Array(Set(fetched.map(\.videoID))), token: token)
            videos = infos.reduce(into: [:]) { $0[$1.id] = $1 }

            let allIDs = Set(fetched.flatMap { $0.all.map(\.id) })
            // Allererster Start: nichts als „neu“ markieren, sonst leuchtet alles.
            if seen.isEmpty { seen = allIDs }
            let arrived = firstLoadThisSession ? [] : allIDs.subtracting(knownIDs)
            knownIDs = allIDs
            firstLoadThisSession = false

            threads = fetched
            for c in fetched.flatMap(\.all) where assessment(for: c) == nil {
                assessments[c.id] = Sentiment.local(c)
            }
            lastRefresh = Date()
            status = ""
            save()

            if aiEnabled, !aiKey.isEmpty { await runAI() }
            if notify, !arrived.isEmpty { notifyArrivals(arrived) }
        } catch {
            status = ""
            errorMessage = error.localizedDescription
        }
    }

    /// KI-Einschätzung für alles, was noch keine hat — in Paketen, gedeckelt.
    private func runAI() async {
        let pending = Array(threads.flatMap(\.all)
            .filter { !(assessment(for: $0)?.byAI ?? false) }
            .prefix(120))
        guard !pending.isEmpty else { return }
        let assessor = AIAssessor(apiKey: aiKey, model: aiModel)
        status = "KI-Einschätzung für \(pending.count) Kommentare …"
        do {
            for start in stride(from: 0, to: pending.count, by: 40) {
                let batch = Array(pending[start..<min(start + 40, pending.count)])
                let results = try await assessor.assess(batch)
                for (id, a) in results { assessments[id] = a }
            }
            save()
            status = ""
        } catch {
            status = ""
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Aktionen

    /// Beim Verlassen eines Videos: alles darin gilt als gelesen.
    func markSeen(videoID: String?) {
        let ids = threads(for: videoID).flatMap { $0.all.map(\.id) }
        guard !ids.isEmpty else { return }
        seen.formUnion(ids)
        save()
    }

    @discardableResult
    func archive(_ comment: Comment) -> URL? {
        let ctx = EvidenceContext(comment: comment, parent: parent(of: comment),
                                  video: videos[comment.videoID],
                                  channelTitle: auth.channelName ?? "",
                                  capturedAt: Date())
        do {
            let folder = try Evidence.save(ctx, into: URL(fileURLWithPath: evidenceFolder, isDirectory: true))
            archived[comment.id] = folder.path
            save()
            return folder
        } catch {
            errorMessage = "Sichern fehlgeschlagen: \(error.localizedDescription)"
            return nil
        }
    }

    /// Kommentar auf YouTube ausblenden. Auf Wunsch vorher sichern — schlägt das
    /// Sichern fehl, wird NICHT entfernt: lieber ein stehender Kommentar als ein
    /// verlorener Beweis.
    func remove(_ comment: Comment, banAuthor: Bool, archiveFirst: Bool) async -> Bool {
        var folder = archived[comment.id]
        if archiveFirst, folder == nil {
            guard let saved = archive(comment) else { return false }
            folder = saved.path
        }
        do {
            let token = try await auth.validAccessToken()
            try await YouTubeAPI.reject(commentID: comment.id, banAuthor: banAuthor, token: token)
        } catch {
            errorMessage = "Entfernen fehlgeschlagen: \(error.localizedDescription)"
            return false
        }
        removed[comment.id] = RemovedRecord(comment: comment, removedAt: Date(),
                                            bannedAuthor: banAuthor, evidenceFolder: folder)
        threads = threads.compactMap { thread in
            if thread.top.id == comment.id { return nil }
            var t = thread
            t.replies.removeAll { $0.id == comment.id }
            return t
        }
        save()
        return true
    }

    #if DEBUG
    /// Nur für den Prüfstand: Daten ohne YouTube einspielen.
    func loadSample(threads: [CommentThread], videos: [VideoInfo], seen: Set<String>) {
        self.threads = threads.sorted { $0.latest > $1.latest }
        self.videos = videos.reduce(into: [:]) { $0[$1.id] = $1 }
        self.seen = seen
        for c in threads.flatMap(\.all) { assessments[c.id] = Sentiment.local(c) }
    }
    #endif

    // MARK: - Mitteilungen

    private func requestNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyArrivals(_ ids: Set<String>) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let arrived = threads.flatMap(\.all).filter { ids.contains($0.id) }
        guard let first = arrived.first else { return }
        let critical = arrived.filter { assessment(for: $0)?.mood == .negative || assessment(for: $0)?.flag != nil }

        let content = UNMutableNotificationContent()
        content.title = arrived.count == 1 ? "Neuer Kommentar" : "\(arrived.count) neue Kommentare"
        content.body = critical.isEmpty
            ? "\(first.authorName): \(first.text.prefix(120))"
            : "davon \(critical.count) negativ oder auffällig — \(critical[0].authorName): \(critical[0].text.prefix(90))"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Ablage

    private struct Persisted: Codable {
        var seen: [String]
        var archived: [String: String]
        var removed: [String: RemovedRecord]
        var assessments: [String: Assessment]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        seen = Set(p.seen)
        archived = p.archived
        removed = p.removed
        assessments = p.assessments
    }

    private func save() {
        let p = Persisted(seen: Array(seen), archived: archived, removed: removed, assessments: assessments)
        if let data = try? JSONEncoder().encode(p) { try? data.write(to: fileURL, options: .atomic) }
    }
}
