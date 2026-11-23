# Lotse – Hinweise für Claude

Lotse ist eine Notch-/Insel-App für macOS (Swift Package, AppKit + SwiftUI, kein Xcode-Projekt). Diese Datei sagt dir, wie du sie für jemanden installierst und einrichtest und worauf du beim Weiterbauen achten musst. Die Fallstricke unten sind alle echt vorgekommen.

## Installieren (wenn dich jemand darum bittet)

Sprich Deutsch und in einfachen Worten; die Person ist nicht unbedingt Entwicklerin.

1. **Repo holen**, falls noch nicht da – nach `~/Lotse`, nicht in einen temporären Ordner (dort liegt später auch der Weg zum Aktualisieren):
   `git clone https://github.com/trostdennie-ship-it/lotse.git ~/Lotse`
   Das Repo ist öffentlich, eine Anmeldung bei GitHub ist nicht nötig. Fehlt `git`, bietet macOS die Command Line Tools an – siehe nächster Schritt.
2. **`~/Lotse/install.sh` ausführen.** Lies die Ausgabe:
   - „Command Line Tools fehlen“ → es hat sich ein Fenster von Apple geöffnet. Bitte die Person, dort auf „Installieren“ zu klicken, warte, bis sie fertig meldet, und starte das Skript erneut.
   - Fragt macOS nach dem Schlüsselbund (beim Signieren), soll die Person „Immer erlauben“ wählen und ihr Mac-Passwort selbst eingeben.
   - Der Bau dauert ein bis zwei Minuten. Lass den Befehl bis zu zehn Minuten laufen.
3. **Prüfen, dass Lotse läuft:** `pgrep -x Lotse` und `tail -20 ~/Library/Logs/Lotse.log` (dort steht „Lotse gestartet“).
4. **Durch den Assistenten führen.** Er öffnet sich beim ersten Start von selbst (Fenster „Lotse einrichten“). Du siehst ihn nicht – erkläre der Person die Schritte und lies den Stand nach jedem Schritt aus
   `~/Library/Application Support/Lotse/einrichtung.txt` (wird alle fünf Sekunden aktualisiert).
   - **Claude:** Knopf „Mit Claude verbinden“. Ersatzweise `/Applications/Lotse.app/Contents/MacOS/Lotse --connect-claude`. Danach gelten die Hooks erst für neue Sessions – auch für diese hier erst nach einem Neustart.
   - **Kalender:** „Kalenderzugriff erlauben“, im macOS-Dialog „Vollzugriff erlauben“.
   - **Mitteilungen:** Festplattenvollzugriff für Lotse einschalten; macOS startet Lotse dabei neu.
   - **Extras:** nach Geschmack.
5. **Abschluss:** `einrichtung.txt` noch einmal lesen, offene Punkte nennen, und sagen, dass in dieser Session erst nach einem Neustart etwas in der Insel erscheint.

### Was du dabei nicht tun darfst

- **Keine Freigaben selbst erteilen.** Kalender, Festplattenvollzugriff, Bedienungshilfen, Bildschirmaufnahme, Mikrofon: Das klickt die Person in den Systemeinstellungen. Kein `tccutil`, kein Schreiben in TCC-Datenbanken, keine Steuerung der Systemeinstellungen per Skript.
- **Keine Klicks in die Insel simulieren.** Synthetische Klicks landen in der App darunter. Lass die Person klicken und lies im Protokoll nach („Klick in Insel …“).
- **`~/.claude/settings.json` nicht von Hand umschreiben.** Dafür gibt es `--connect-claude` und `--disconnect-claude`; sie lassen fremde Einträge stehen und legen `settings.json.vor-lotse` als Sicherung an. Ist die Datei kein gültiges JSON, bricht Lotse ab – dann zeig der Person das Problem, statt die Datei zu überschreiben.

## Wenn etwas nicht geht

| Beobachtung | Ursache und Abhilfe |
|---|---|
| Insel zeigt keine Claude-Session | Hooks fehlen (`einrichtung.txt`) oder die Session lief schon vor dem Verbinden – neu starten. Hooks melden nur, solange Lotse läuft (`pgrep -x Lotse`). |
| Keine Mitteilungen anderer Apps | Festplattenvollzugriff fehlt, oder die App darf selbst nicht melden. In Systemeinstellungen → Mitteilungen muss für die App „Mitteilungen erlauben“ und „Mitteilungszentrale“ an sein. Wer keine Banner will, nimmt nur den Haken bei „Schreibtisch“ heraus. |
| Gmail kommt nicht an | Kommt als Web-Push aus Chrome: in Gmail „Desktop-Benachrichtigungen“ einschalten und in `chrome://settings/content/notifications` mail.google.com erlauben. |
| Termine doppelt | Google Kalender meldet zusätzlich über Chrome. `calendar.google.com` in `chrome://settings/content/notifications` blockieren – Lotse erinnert selbst. |
| Termin-Meldung aus einem Kalender, der gar nicht angezeigt wird | Die macOS-Kalender-App meldet unabhängig von Lotse. Lotse verwirft solche Mitteilungen anhand des Titels, wenn der Kalender in Einstellungen → Kalender ausgeschaltet ist. |
| Kalender leer | Konto fehlt in Systemeinstellungen → Internetaccounts (dort „Kalender“ einschalten), oder der Kalender ist in Lotse ausgeschaltet. |
| Nutzungsstände (5 Stunden / Woche) leer | Claude Code ist im Terminal nicht angemeldet: `claude` starten, `/login`. |
| Freigaben nach jedem Neubau weg | Das Zertifikat „Lotse Dev“ fehlt, die App ist nur ad hoc signiert. `./install.sh` legt es an. |
| Fenster rasten nicht ein | Bedienungshilfen für Lotse fehlen. |
| Mitschnitt startet nicht | Beim ersten Mal fragt macOS nach Bildschirm-/Systemaudioaufnahme und Mikrofon; falls es danach nicht läuft, Lotse neu starten. |

Protokoll: `~/Library/Logs/Lotse.log`. Einstellungen: `defaults read local.lotse.app`.

## Weiterbauen

- **Bauen und installieren:** `./build.sh` (signiert mit „Lotse Dev“, installiert nach `/Applications/Lotse.app`, startet neu). `./build.sh --no-install` baut nur.
- **Aufbau:** `main.swift` (Fenster, Maus, Start, Probebilder), `Model.swift`, `Views.swift` (die Insel), `Sources.swift` (Kalender, Claude, Mitteilungen, Musik), `Settings.swift`, `Onboarding.swift` (Assistent), `ClaudeHooks.swift` (Einträge in settings.json), dazu je eine Datei pro Baustein (Recorder, Transcriber, Clipboard, Snap, Weather, Risk, NoticeFilter …). `Entwurf/` ist nicht im Build.
- **Prüfen ohne Bildschirm:** `screencapture` und Bildschirm-Werkzeuge sehen die Insel nicht. Stattdessen
  `.build/release/Lotse --snapshot <png> <modus> [--notch] [--amber]` (Modi u. a. `compact`, `peek`, `ask`, `question`, `expanded`, `work`, `mix`, `stow`, `week`) und
  `.build/release/Lotse --snapshot-setup <png> <0…5>` für den Assistenten. In Probebildern fehlen Inhalte von `ScrollView` und Textfeldern; im Assistenten-Bild stimmen Fensterfarben und Knopfbeschriftungen nicht – das ist nur das Rendering.
- **Selbsttest:** `.build/release/Lotse --selftest` (Risiko-Regeln, Einrast-Zonen, Hook-Einträge).
- **Beispiele in der echten Insel:** eine JSON-Datei mit `"hook_event_name":"LotseDemo"` (Felder `title`, `body`, `brief`, `symbol`, `card`, `app`) oder `"LotseTour"` nach `~/Library/Application Support/Lotse/events/` legen.

### Was man wissen muss, bevor man etwas ändert

- **Modale Dialoge vermeiden** (`runModal`). SwiftUI misst die Pille währenddessen nicht neu, die Insel klappt dann an der falschen Stelle auf. `panel.begin` nehmen und die Insel vorher einklappen.
- **Kein `TabView` für Fenster mit vielen Reitern.** macOS 26 versteckt Reiter hinter einem Pfeil, sobald der Platz knapp wird. Einstellungen und Assistent haben deshalb eigene Leisten.
- **Beim ersten Start keine Dialoge aus dem Nichts.** Kalender und Bedienungshilfen fragt erst der Assistent an (`OnboardingWindow.done`).
- **Die Mitteilungen kommen aus der Datenbank der Mitteilungszentrale** (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`), nur lesend. Das ist kein öffentliches Format und kann sich mit macOS ändern.
- **Sprung zur Session und Sitzungstitel** nutzen Interna der Claude-App (`claude://code/continue?session=…`, `~/Library/Application Support/Claude/claude-code-sessions/`); die Nutzungsstände fragt `Usage.swift` beim mitgelieferten Claude Code ab. Beides kann mit einem Update der Claude-App brechen.
- **Der Freigabe-Hook wartet höchstens 45 Sekunden** auf eine Antwort aus der Insel und endet sonst ohne Entscheidung – dann fragt Claude selbst. Bei `AskUserQuestion` wartet er gar nicht.
- **Außerhalb von „Dokumente“ signieren.** Der Finder hängt dort Attribute an, an denen `codesign` scheitert; `build.sh` baut deshalb in `$TMPDIR`.
- **Texte in der Oberfläche sind deutsch**, mit „du“. Keine Notizen, keine Aufgabenliste, das Pixel-Segelboot bleibt das Maskottchen.
