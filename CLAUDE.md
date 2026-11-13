# Tadpole

A native macOS mod manager for Baldur's Gate 3: Nexus browsing and
collections, load order, updates, Script Extender, save backups.

## Layout

- `project.yml` is the XcodeGen spec for `Tadpole.xcodeproj`. Edit it, then `xcodegen generate`; never edit the `.xcodeproj`. The version is `MARKETING_VERSION` there.
- `App/` the SwiftUI app. `AppModel.swift` and its `+Nexus`, `+Profiles`, `+Saves`, `+ScriptExtender`, `+Updates` … extensions hold state and actions.
- `TadpoleCore/` Swift package, no UI. Tests in `TadpoleCore/Tests/TadpoleCoreTests/`.
- The Script Extender's log is read from `~/Library/Application Support/BG3SE/logs/` (`ScriptExtenderLog.swift`).

## Build and check

- Build: `./build_app.sh` → `dist/Tadpole.app` (builds in ~/Library/Caches, away from iCloud).
- Tests: `swift test --package-path TadpoleCore --scratch-path ~/Library/Developer/Tadpole/test-build`.
- Never test against a real game install or real saves.
- Release: `tools/release.sh <version>` (settings in `release.conf`). Use the mac-release skill.

## Git

- Commit after each working change, with a message that says what the user can now do.
