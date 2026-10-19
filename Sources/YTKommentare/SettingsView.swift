import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var auth: AuthManager
    @EnvironmentObject var store: CommentStore
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen").font(.headline)
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()

            Form {
                Section("YouTube-Anmeldung") {
                    TextField("Client-ID", text: $auth.clientID)
                    SecureField("Client-Secret", text: $auth.clientSecret)
                    HStack {
                        Button("Aus YT Producer übernehmen") {
                            message = auth.importCredentialsFromProducer()
                                ? "Übernommen." : "In YT Producer sind keine Zugangsdaten hinterlegt."
                        }
                        Spacer()
                        if auth.isSignedIn {
                            Text(auth.channelName.map { "Angemeldet: \($0)" } ?? "Angemeldet")
                                .foregroundStyle(.green).font(.callout)
                            Button("Abmelden") { auth.signOut() }
                        } else {
                            Button(busy ? "Warte auf Browser …" : "Anmelden") {
                                busy = true
                                Task {
                                    do {
                                        try await auth.signIn()
                                        await store.refresh()
                                    } catch { message = error.localizedDescription }
                                    busy = false
                                }
                            }
                            .disabled(busy || auth.clientID.isEmpty || auth.clientSecret.isEmpty)
                        }
                    }
                    Text("Berechtigung: youtube.force-ssl — die einzige, mit der YouTube Kommentare über eine Anmeldung herausgibt und moderieren lässt. Das Token liegt nur im Schlüsselbund dieses Macs.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Überwachung") {
                    Picker("Abruf alle", selection: $store.intervalMinutes) {
                        Text("5 Minuten").tag(5)
                        Text("10 Minuten").tag(10)
                        Text("15 Minuten").tag(15)
                        Text("30 Minuten").tag(30)
                    }
                    Toggle("Mitteilung bei neuen Kommentaren", isOn: $store.notify)
                    Text("Ein Abruf kostet etwa 5 Einheiten des YouTube-Tageskontingents — bei 10 Minuten rund 700 am Tag, solange die App offen ist. Das Kontingent teilt sich die App mit YT Producer, wenn beide dieselbe Client-ID nutzen.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Beweissicherung") {
                    HStack {
                        Text(store.evidenceFolder).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Ändern…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url { store.evidenceFolder = url.path }
                        }
                        Button("Zeigen") {
                            let url = URL(fileURLWithPath: store.evidenceFolder)
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                Section("KI-Einschätzung (optional)") {
                    Toggle("Stimmung per KI einschätzen und Auffälliges markieren", isOn: $store.aiEnabled)
                    SecureField("OpenAI-API-Schlüssel", text: $store.aiKey)
                    TextField("Modell", text: $store.aiModel)
                    Text("Genauer als die macOS-Sprachanalyse und markiert mögliche Beleidigungen, Drohungen oder Verhetzung. Kommentartexte gehen dafür an OpenAI. Die Markierung ist ein Hinweis, keine rechtliche Prüfung.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 600, height: 640)
    }
}
