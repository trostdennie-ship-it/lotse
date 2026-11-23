# Lotse

Lotse ist eine kleine Insel oben in der Mitte des Mac-Bildschirms – am Notch des MacBooks oder als Pille auf einem externen Monitor. Sie zeigt, woran Claude Code gerade arbeitet, den nächsten Termin, Musik und die Mitteilungen anderer Apps. Ruht der Zeiger darauf, klappt sie auf.

## Was Lotse kann

- **Claude Code im Blick:** laufende Sessions mit Status, Fortschritt und Arbeitsdauer; Freigaben direkt in der Insel erlauben oder ablehnen; riskante Befehle werden markiert; Fragen von Claude erscheinen als Frage.
- **Kalender:** nächster Termin, Wochenübersicht, Erinnerung fünf Minuten vorher und zum Beginn, „Beitreten“ bei Zoom-, Teams- und Meet-Links.
- **Mitteilungen:** spiegelt, was andere Apps melden (Mail, Slack, Chrome …), mit einem Filter dafür, was die Insel aufklappen darf.
- **Arbeitsplatz:** Fokus-Timer, Verlauf der Zwischenablage, Mitschnitt von Calls (nur Ton) mit Transkript auf dem Gerät.
- **Ablage:** Dateien auf die Insel ziehen und kurz parken, Bilder umwandeln.
- **Lautstärke:** Gesamtlautstärke, Ausgabegerät wechseln, Wiedergabe steuern.
- **Kleinigkeiten:** Wetter, Schnellzugriff auf Ordner, Fenster an den Bildschirmrand einrasten, Besprechungsmodus.

## Voraussetzungen

- macOS 26 (Tahoe) oder neuer
- die Claude-App für den Mac mit dem Reiter „Code“ (oder Claude Code im Terminal)
- Apples Command Line Tools – die Installation bietet sie an, falls sie fehlen

## Installieren

Am einfachsten über Claude. Im Reiter „Code“ der Claude-App einen Ordner wählen und schreiben:

> Installiere Lotse aus dem Repo `trostdennie-ship-it/lotse` und führe mich durch die Einrichtung. Halte dich an die CLAUDE.md im Repo.

Von Hand geht es so:

```bash
git clone https://github.com/trostdennie-ship-it/lotse.git ~/Lotse
```

```bash
~/Lotse/install.sh
```

Das Skript prüft die Voraussetzungen, legt einmalig ein eigenes Signatur-Zertifikat an, baut die App nach `/Programme` und startet sie. Danach öffnet sich der Einrichtungsassistent.

## Einrichten

Der Assistent führt durch vier Dinge. Alles ist freiwillig und lässt sich später nachholen (Rechtsklick auf die Insel → Einstellungen … → Hilfe → „Einrichtung erneut öffnen“).

| Schritt | Wozu | Was du tust |
|---|---|---|
| Claude verbinden | Sessions, Status und Freigaben in der Insel | ein Klick; danach Claude-Sessions neu starten |
| Kalender | Termine und Erinnerungen | „Vollzugriff erlauben“ im Dialog von macOS |
| Mitteilungen | Mitteilungen anderer Apps | Festplattenvollzugriff für Lotse einschalten, Lotse neu starten |
| Extras | Fenster einrasten, Wetter-Ort, Farben | nach Geschmack |

Den Stand der Einrichtung schreibt Lotse laufend in eine Textdatei:

```bash
cat "$HOME/Library/Application Support/Lotse/einrichtung.txt"
```

## Was Lotse auf dem Mac anfasst

- `~/.claude/settings.json` – beim Verbinden mit Claude kommen Hook-Einträge dazu. Vorher entsteht einmalig die Sicherung `settings.json.vor-lotse`. Fremde Einträge bleiben stehen.
- `~/Library/Application Support/Lotse/` – Hook-Skripte, Ereignisse, Filterregeln.
- `~/Library/Logs/Lotse.log` – Protokoll.
- `~/Documents/Lotse Mitschnitte/` – Aufnahmen und Transkripte, nur wenn du selbst aufnimmst.
- Anmelde-Schlüsselbund – das selbst erzeugte Zertifikat „Lotse Dev“.

Nach außen geht nur der Ortsname fürs Wetter (an Open-Meteo). Die Hooks geben weder Dateiinhalte noch Prompts weiter, und alles bleibt auf dem Mac.

## Aktualisieren und entfernen

```bash
cd ~/Lotse && git pull && ./build.sh
```

```bash
~/Lotse/uninstall.sh
```

## Für Neugierige

Swift Package (AppKit und SwiftUI), gebaut ohne Xcode. `./build.sh` baut, signiert und installiert. `Lotse --selftest` prüft die Risiko-Regeln, die Einrast-Zonen und das Eintragen der Hooks; `Lotse --snapshot <png> <modus>` rendert die Insel als Bild, ohne dass sie auf dem Bildschirm erscheint. Mehr dazu in der [CLAUDE.md](CLAUDE.md).
