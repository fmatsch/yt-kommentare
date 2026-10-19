import SwiftUI

enum SidebarItem: Hashable {
    case all
    case removed
    case video(String)
}

struct ContentView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var store: CommentStore
    @State private var selection: SidebarItem? = .all
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            detail
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    if store.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    if !store.status.isEmpty {
                        Text(store.status).font(.caption).foregroundStyle(.secondary)
                    } else if let last = store.lastRefresh {
                        Text("Stand \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                            .help("Nächster Abruf in höchstens \(store.intervalMinutes) Minuten")
                    }
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Abrufen", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing || !auth.isSignedIn)
                    .help("Jetzt abrufen (⌘R)")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingSettings = true } label: {
                    Label("Einstellungen", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: selection) { old, _ in
            // Was man gesehen hat, ist beim Verlassen nicht mehr „neu“.
            switch old {
            case .video(let id)?: store.markSeen(videoID: id)
            case .all?:           store.markSeen(videoID: nil)
            default: break
            }
        }
        .task { store.startMonitoring() }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(auth)
                .environmentObject(store)
        }
        .alert("Fehler", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Seitenleiste

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                sidebarRow(title: "Alle Kommentare", symbol: "bubble.left.and.bubble.right",
                           count: store.unseenCount(videoID: nil))
                    .tag(SidebarItem.all)
                if !store.removed.isEmpty {
                    sidebarRow(title: "Entfernt", symbol: "trash", count: 0,
                               trailing: "\(store.removed.count)")
                        .tag(SidebarItem.removed)
                }
            }
            Section("Videos · neuester Kommentar zuerst") {
                ForEach(store.videoOrder) { video in
                    VideoRow(video: video)
                        .tag(SidebarItem.video(video.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func sidebarRow(title: String, symbol: String, count: Int, trailing: String? = nil) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if count > 0 { NewBadge(count: count) }
            if let trailing { Text(trailing).foregroundStyle(.secondary).font(.caption) }
        }
    }

    // MARK: - Hauptbereich

    @ViewBuilder
    private var detail: some View {
        if !auth.isSignedIn {
            SignInPrompt(showSettings: { showingSettings = true })
        } else {
            switch selection {
            case .video(let id)?:
                CommentListView(videoID: id)
            case .removed?:
                RemovedListView()
            default:
                CommentListView(videoID: nil)
            }
        }
    }
}

// MARK: - Zeile in der Seitenleiste

struct VideoRow: View {
    let video: VideoInfo
    @EnvironmentObject var store: CommentStore

    var body: some View {
        let threads = store.threads(for: video.id)
        HStack(alignment: .top, spacing: 8) {
            AsyncImage(url: video.thumbnailURL) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title).font(.callout).lineLimit(2)
                HStack(spacing: 6) {
                    if let latest = store.latest(videoID: video.id) {
                        Text(Format.relative(latest)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    let new = store.unseenCount(videoID: video.id)
                    if new > 0 { NewBadge(count: new) }
                }
                MoodBar(counts: store.moodCounts(threads)).frame(height: 4)
            }
        }
        .padding(.vertical, 3)
    }
}

struct NewBadge: View {
    let count: Int
    var body: some View {
        Text("\(count) neu")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(Capsule().fill(Color.accentColor))
            .foregroundStyle(.white)
    }
}

// MARK: - Nicht angemeldet

struct SignInPrompt: View {
    @EnvironmentObject var auth: AuthManager
    let showSettings: () -> Void
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Bei YouTube anmelden").font(.title2.weight(.semibold))
            Text("Die App braucht die Berechtigung, Kommentare zu lesen und zu moderieren.\nDafür mit dem Konto von ORF Kontext anmelden und bei Google den richtigen Kanal wählen.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if auth.clientID.isEmpty || auth.clientSecret.isEmpty {
                Button("Zugangsdaten aus YT Producer übernehmen") {
                    if !auth.importCredentialsFromProducer() {
                        error = "In YT Producer sind keine Zugangsdaten hinterlegt — bitte in den Einstellungen eintragen."
                    }
                }
                Button("Einstellungen öffnen", action: showSettings).buttonStyle(.link)
            } else {
                Button {
                    busy = true
                    Task {
                        do { try await auth.signIn() } catch { self.error = error.localizedDescription }
                        busy = false
                    }
                } label: {
                    Label(busy ? "Warte auf Browser …" : "Anmelden", systemImage: "person.crop.circle.badge.checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
            if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
        }
        .padding(40)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum Format {
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_AT")
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "de_AT")))
    }
}
