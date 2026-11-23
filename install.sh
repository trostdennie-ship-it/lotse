#!/bin/sh
# Installiert Lotse auf diesem Mac: prüft die Voraussetzungen, legt einmalig ein eigenes
# Signatur-Zertifikat an, baut die App und startet sie.  Aufruf: ./install.sh
set -e
cd "$(dirname "$0")"

say() { printf '\n== %s\n' "$1"; }
die() { printf '\nABBRUCH: %s\n' "$1" >&2; exit 1; }

say "Voraussetzungen"
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 26 ] || die "Lotse braucht macOS 26 (Tahoe) oder neuer. Hier läuft $(sw_vers -productVersion)."
echo "macOS $(sw_vers -productVersion) – passt."
if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find swift >/dev/null 2>&1; then
    xcode-select --install >/dev/null 2>&1 || true
    die "Die Command Line Tools von Apple fehlen. Es hat sich ein Fenster zum Installieren geöffnet – das dauert einige Minuten. Danach ./install.sh noch einmal starten."
fi
echo "Swift: $(xcrun swift --version 2>&1 | head -1)"
[ -x /usr/bin/jq ] || die "/usr/bin/jq fehlt (gehört ab macOS 15 zum System). Ohne jq können die Claude-Hooks nichts melden."

# Eigenes Zertifikat: Damit erkennt macOS Lotse nach jedem Neubau wieder, und erteilte Freigaben
# (Kalender, Festplattenvollzugriff, Bedienungshilfen …) bleiben erhalten. Es verlässt diesen Mac nie.
say "Signatur-Zertifikat „Lotse Dev“"
if security find-identity -p codesigning | grep -q "Lotse Dev"; then
    echo "Schon vorhanden."
else
    T=$(mktemp -d)
    trap 'rm -rf "$T"' EXIT
    cat > "$T/cfg" <<'CFG'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=Lotse Dev
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CFG
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -keyout "$T/key.pem" -out "$T/cert.pem" -days 3650 -config "$T/cfg" >/dev/null 2>&1 \
        || die "Zertifikat konnte nicht erzeugt werden (openssl)."
    P=$(uuidgen)
    /usr/bin/openssl pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" -name "Lotse Dev" -out "$T/lotse.p12" -passout "pass:$P" >/dev/null 2>&1 \
        || die "Zertifikat konnte nicht verpackt werden (openssl pkcs12)."
    security import "$T/lotse.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$P" -T /usr/bin/codesign >/dev/null \
        || die "Zertifikat ließ sich nicht in den Anmelde-Schlüsselbund legen."
    security find-identity -p codesigning | grep -q "Lotse Dev" || die "Zertifikat wurde angelegt, wird aber nicht gefunden."
    echo "Angelegt. Fragt macOS beim Signieren nach dem Schlüsselbund, bitte „Immer erlauben“ wählen."
fi

say "Bauen und installieren"
./build.sh

say "Fertig"
cat <<'TXT'
Lotse liegt in /Programme und läuft. Beim ersten Start öffnet sich der Einrichtungsassistent
(sonst: Rechtsklick auf die Insel → Einstellungen … → Hilfe → „Einrichtung erneut öffnen“).

Stand der Einrichtung, jederzeit:
  cat "$HOME/Library/Application Support/Lotse/einrichtung.txt"
Protokoll:
  tail -30 "$HOME/Library/Logs/Lotse.log"
TXT
