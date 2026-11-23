#!/bin/sh
# Entfernt Lotse: beendet die App, nimmt die Hooks aus Claude Code und löscht die App.
# Einstellungen, Protokoll und Mitschnitte bleiben liegen – die Pfade stehen am Ende.
APP=/Applications/Lotse.app
osascript -e 'quit app "Lotse"' 2>/dev/null || true
sleep 1
if [ -x "$APP/Contents/MacOS/Lotse" ]; then
    "$APP/Contents/MacOS/Lotse" --disconnect-claude || echo "Hinweis: Hooks bitte von Hand aus ~/.claude/settings.json entfernen."
fi
rm -rf "$APP"
cat <<'TXT'
Lotse ist entfernt. Liegen geblieben (bei Bedarf selbst löschen):
  ~/Library/Application Support/Lotse      Hook-Skripte, Filterregeln
  ~/Library/Logs/Lotse.log                 Protokoll
  ~/Documents/Lotse Mitschnitte            deine Aufnahmen
  Einstellungen:  defaults delete local.lotse.app
  Zertifikat „Lotse Dev“ in der Schlüsselbundverwaltung (Anmeldung)
TXT
