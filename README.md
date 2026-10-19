# YT Kommentare

Überwacht die Kommentare auf dem YouTube-Kanal ORF Kontext: welches Video,
wie es gerade läuft, darunter die Kommentare — **neuester zuerst**. Kommentare
lassen sich als Beweis sichern und auf YouTube entfernen; eine kleine
Stimmungsanalyse zeigt auf einen Blick, wie die Stimmung ist.

Nicht zu verwechseln mit **CommentMonitor** — der überwacht Leserkommentare
bei derStandard, Kurier und Krone.

## Starten

```bash
./build-app.sh
open "YT Kommentare.app"
```

Beim ersten Start: **„Zugangsdaten aus YT Producer übernehmen“** (macOS fragt
einmal, ob die App Daten einer anderen App lesen darf), dann **„Anmelden“** —
bei Google den Kanal **ORF Kontext** wählen, nicht den persönlichen.

## Aufbau des Fensters

- **Links** die Videos, sortiert nach dem neuesten Kommentar, mit „neu“-Zähler
  und Stimmungsbalken. Oben „Alle Kommentare“ als Gesamtstrom, darunter
  „Entfernt“ mit allem, was von hier aus entfernt wurde.
- **Rechts** das Video mit Aufrufen, Likes und Kommentarzahl, darunter die
  Kommentarstränge. Ein Strang mit neuer Antwort rückt nach oben. Filter:
  Alle · Neu · Negativ · Mit Hinweis · Gesichert, dazu eine Suche.

„Neu“ ist, was seit dem letzten Öffnen des Videos dazugekommen ist. Beim
allerersten Start gilt nichts als neu.

## Sichern (Beweissicherung)

Pro Kommentar ein Ordner in `~/Documents/YT-Kommentare Beweise/`:

| Datei | Inhalt |
|---|---|
| `Beweis.pdf`, `Beweis.png` | alle Angaben lesbar: Wortlaut, Name, Kanal-Adresse und -ID der Person, Veröffentlichung/Bearbeitung, Direktlink, bei Antworten der Ausgangskommentar |
| `kommentar.json` | die unveränderte Antwort der YouTube-API, Zeitpunkt der Sicherung |
| `pruefsummen.txt` | SHA-256 aller Dateien — belegt, dass seit der Sicherung nichts verändert wurde |

Nachprüfen: `shasum -a 256 -c` gegen die Werte in `pruefsummen.txt`.

Keine Rechtsberatung: Für ein Verfahren ist die Sicherung eine gute Grundlage;
ob zusätzlich eine förmliche Beweissicherung nötig ist, klärt am besten die
Rechtsabteilung.

## Entfernen

Blendet den Kommentar auf YouTube aus — wie „Entfernen“ in YouTube Studio
(`comments.setModerationStatus = rejected`). Optional wird die Person auf dem
Kanal gesperrt. Standardmäßig wird **vorher gesichert**; schlägt das Sichern
fehl, wird nicht entfernt.

## Stimmung

- **Lokal** (immer an): Sprachanalyse von macOS — sofort, ohne Netz. Misst den
  **Ton**: Empörung über das Thema zählt als negativ, auch wenn die Person den
  Beitrag unterstützt. Fragen werden auf neutral gestellt.
- **KI** (optional, Einstellungen): mit einem OpenAI-Schlüssel. Genauer, und
  markiert mögliche Beleidigungen, Drohungen, Verhetzung oder Spam. Ein
  Hinweis, keine rechtliche Prüfung. Kommentartexte gehen dafür an OpenAI.

## Kontingent und Berechtigung

- Anmeldung mit `youtube.force-ssl` — die einzige Berechtigung, mit der
  YouTube Kommentare über eine Anmeldung herausgibt und moderieren lässt.
  Das Token liegt nur im Schlüsselbund des Macs.
- Ein Abruf kostet etwa 5 Einheiten (2 Seiten à 100 Stränge, dazu Videos und
  ggf. Antworten), Entfernen 50. Bei 10 Minuten Abstand rund 700 Einheiten
  am Tag, solange die App offen ist — geteilt mit YT Producer, wenn beide
  dieselbe Client-ID nutzen.
- Stränge weiter hinten als die neuesten 200 werden nicht abgerufen; eine
  neue Antwort auf einen sehr alten Kommentar kann deshalb fehlen.

## Prüfstand

`Tests/harness.swift` schickt Kommentare im Originalformat der API durch
Einlesen, Stimmung und Beweissicherung und rendert die Oberfläche als Bild.
