#!/bin/bash
# Packs dist/Tadpole.app into a drag-to-install disk image:
#   ./make_dmg.sh releases/Tadpole.dmg
# The window shows the app, an Applications shortcut, and a note about
# macOS's warning for apps without an Apple Developer ID.
set -euo pipefail
cd "$(dirname "$0")"

OUT="${1:-releases/Tadpole.dmg}"
APP="dist/Tadpole.app"
[ -d "$APP" ] || { echo "Build the app first (./build_app.sh)." >&2; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
# No extended attributes: they break the app's code signature check.
ditto --noextattr --norsrc "$APP" "$STAGE/Tadpole.app"
xattr -cr "$STAGE/Tadpole.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/If macOS blocks Tadpole.txt" <<'NOTE'
Install: drag Tadpole onto the Applications folder.

The first time you open it, macOS may say it can't check Tadpole for
malicious software, because it isn't signed with a paid Apple Developer ID.
To open it anyway:

  1. Try to open Tadpole once, then click Done.
  2. Open System Settings > Privacy & Security.
  3. Scroll down and click "Open Anyway" next to Tadpole, then confirm.

You only do this once; updates install without asking again.

---

Installation : glissez Tadpole sur le dossier Applications.

À la première ouverture, macOS peut dire qu'il ne peut pas vérifier
Tadpole, car l'app n'est pas signée avec un identifiant de développeur
Apple payant. Pour l'ouvrir quand même :

  1. Essayez d'ouvrir Tadpole une fois, puis cliquez sur Terminé.
  2. Ouvrez Réglages Système > Confidentialité et sécurité.
  3. Faites défiler et cliquez sur « Ouvrir quand même » à côté de
     Tadpole, puis confirmez.

Une seule fois suffit : les mises à jour s'installent ensuite sans
redemander.
NOTE

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
hdiutil create -volname "Tadpole" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null 2>&1
echo "Created $OUT"
