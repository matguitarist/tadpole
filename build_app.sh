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

# Signed with the "Tadpole Self-Signed" certificate when it's in the
# Keychain (make_signing_identity.sh), so the app's identity stays the same
# from build to build and macOS asks for Keychain access (the Nexus API key)
# once. REQUIRE_SIGNING=1 (release.sh) stops without it. Signing happens
# here in Caches: this folder may sync with iCloud Drive, which puts Finder
# attributes back on files and makes codesign fail.
STAGED="$DERIVED/Signed/$APP_NAME"
/bin/rm -rf "$STAGED"
mkdir -p "${STAGED:h}"
ditto --noextattr --norsrc "$BUILT" "$STAGED"
if security find-identity -p codesigning | grep -q '"Tadpole Self-Signed"'; then
    ./sign_app.sh "$STAGED" 2>&1 | grep -v "replacing existing signature"
elif [[ -n "${REQUIRE_SIGNING:-}" ]]; then
    echo "No “Tadpole Self-Signed” certificate: run ./make_signing_identity.sh first." >&2
    exit 1
else
    echo "Note: signed ad hoc (run ./make_signing_identity.sh for a stable signature)."
fi

mkdir -p dist
/bin/rm -rf "dist/$APP_NAME"
ditto --noextattr --norsrc "$STAGED" "dist/$APP_NAME"
echo "Built dist/$APP_NAME"
