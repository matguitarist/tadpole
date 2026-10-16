#!/bin/zsh
# Builds a Release "dist/Tadpole.app" with Xcode.
#
# Build products go to ~/Library/Caches (not next to the sources): this
# folder may sync with iCloud Drive, whose extended attributes make
# codesign fail ("resource fork, Finder information, or similar detritus").
set -euo pipefail
cd "${0:A:h}"

# Use full Xcode even if xcode-select still points at the Command Line Tools.
if ! xcodebuild -version >/dev/null 2>&1; then
    XCODE_APP=$(ls -d /Applications/Xcode*.app 2>/dev/null | grep -v Xcodes.app | sort -V | tail -1)
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
fi

DERIVED="$HOME/Library/Caches/Tadpole/DerivedData"
LOG="$DERIVED/build_app.log"
mkdir -p "$DERIVED"
# A failed build must stop here: an older app would still be in DerivedData.
if ! xcodebuild -project Tadpole.xcodeproj -scheme Tadpole -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$DERIVED" build > "$LOG" 2>&1; then
    grep -E "error:" "$LOG" | head -20
    echo "Build failed (full log: $LOG)"
    exit 1
fi

APP_NAME="Tadpole.app"
BUILT="$DERIVED/Build/Products/Release/$APP_NAME"
[[ -d "$BUILT" ]] || { echo "Build failed"; exit 1; }

# Signed with a self-signed certificate when one is in the Keychain, so the
# app's identity stays the same from build to build and macOS asks for
# Keychain access (the Nexus API key) once. Starseed's certificate works
# too. SIGNING_IDENTITY picks another one.
STAGED="$DERIVED/Signed/$APP_NAME"
/bin/rm -rf "$STAGED"
mkdir -p "${STAGED:h}"
ditto --noextattr --norsrc "$BUILT" "$STAGED"
IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
    for candidate in "Tadpole Self-Signed" "Starseed Self-Signed"; do
        if security find-identity -p codesigning | grep -q "\"$candidate\""; then IDENTITY="$candidate"; break; fi
    done
fi
if [[ -n "$IDENTITY" ]]; then
    xattr -cr "$STAGED"
    # Keep Xcode's entitlements, except get-task-allow (debugging only).
    ENTITLEMENTS=$(mktemp -t tadpole-entitlements).plist
    codesign -d --entitlements - --xml "$STAGED" > "$ENTITLEMENTS" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ENTITLEMENTS" >/dev/null 2>&1 || true
    codesign --force --timestamp=none --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$STAGED" 2>&1 \
        | grep -v "replacing existing signature" || true
    /bin/rm -f "$ENTITLEMENTS"
    codesign --verify --deep --strict "$STAGED"
    echo "Signed with “$IDENTITY”"
else
    echo "Note: signed ad hoc (no self-signed certificate in the Keychain)."
fi

mkdir -p dist
/bin/rm -rf "dist/$APP_NAME"
ditto --noextattr --norsrc "$STAGED" "dist/$APP_NAME"
echo "Built dist/$APP_NAME"
