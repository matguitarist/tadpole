#!/bin/bash
# Publishes a release of Tadpole: builds it, uploads a disk image (for new
# installs) and a zip (for Sparkle updates) to GitHub Releases, and updates
# appcast.xml (the feed Sparkle checks) on main.
#
# Before running: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in
# project.yml (Sparkle compares the build number), run `xcodegen generate`,
# write release-notes/<version>.md (shown in the update window and on
# GitHub), and commit. Needs `gh` logged in, Tadpole's Sparkle key in the
# Keychain (account "tadpole") and the "Tadpole Self-Signed" certificate
# (make_signing_identity.sh).
#
# ./release.sh --local http://127.0.0.1:8765/ only stages the zip and the
# feed in releases/ with that download address, to try the update from a
# local server (TADPOLE_FEED_URL) before publishing.
set -euo pipefail
cd "$(dirname "$0")"

LOCAL_PREFIX=""
[ "${1:-}" = "--local" ] && LOCAL_PREFIX="${2:?--local needs a URL prefix}"

REPO="matguitarist/tadpole"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
BUILD=$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *"\(.*\)"/\1/p' project.yml | head -1)
TAG="v$VERSION"
SPARKLE_BIN="$HOME/Library/Caches/Tadpole/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "Couldn't read the version from project.yml" >&2; exit 1; }
NOTES="release-notes/$VERSION.md"
[ -s "$NOTES" ] || { echo "Write $NOTES first: it's what users see in the update window." >&2; exit 1; }
if [ -z "$LOCAL_PREFIX" ]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Commit your changes first." >&2; exit 1
    fi
    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        echo "$TAG is already released: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION." >&2; exit 1
    fi
fi

echo "==> Releasing Tadpole $VERSION (build $BUILD)"
REQUIRE_SIGNING=1 ./build_app.sh

# Only the new zip in the folder: the feed lists the latest version, which
# is all Sparkle needs.
STAGING="releases/$TAG"
rm -rf "$STAGING" && mkdir -p "$STAGING"
ZIP="$STAGING/Tadpole-$VERSION.zip"
ditto -c -k --norsrc --noextattr --keepParent "dist/Tadpole.app" "$ZIP"
# Same name as the zip: generate_appcast embeds it as the update's notes.
cp "$NOTES" "$STAGING/Tadpole-$VERSION.md"
"$SPARKLE_BIN/generate_appcast" --account tadpole \
    --download-url-prefix "${LOCAL_PREFIX:-https://github.com/$REPO/releases/download/$TAG/}" \
    --embed-release-notes \
    "$STAGING"

if [ -n "$LOCAL_PREFIX" ]; then
    echo "==> Staged in $STAGING (feed: ${LOCAL_PREFIX}appcast.xml)"
    exit 0
fi

# The disk image is for first installs. A fixed name keeps the
# ".../releases/latest/download/Tadpole.dmg" link working. It's made after
# the appcast so generate_appcast only sees the zip.
DMG="releases/Tadpole.dmg"
./make_dmg.sh "$DMG"

git push origin HEAD
gh release create "$TAG" "$DMG" "$ZIP" --repo "$REPO" --title "Tadpole $VERSION" --notes-file "$NOTES"

# Publish the feed last, once the zip it points to is online.
cp "$STAGING/appcast.xml" appcast.xml
git add appcast.xml
git commit -m "Update appcast for $VERSION"
git push origin HEAD
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
