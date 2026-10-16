# Developing Tadpole

Tadpole is a SwiftUI app (macOS 14+) with its file formats and rules in a
local Swift package, `TadpoleCore`, kept free of UI code and tested on its
own. It's a sibling of [Starseed](https://github.com/matguitarist/starseed),
the Stardew Valley mod manager, and borrows its structure.

```
tadpole/
├── project.yml        # XcodeGen spec (xcodegen generate)
├── App/               # SwiftUI app: model, views, String Catalog (en, fr)
└── TadpoleCore/       # Swift package, no UI
    ├── Sources/TadpoleCore/
    │   ├── Pak.swift          # Larian .pak (LSPK v18) reader, LZ4 via Compression
    │   ├── LSX.swift          # .lsx (Larian XML) parser
    │   ├── ModuleInfo.swift   # meta.lsx: UUID, name, version, dependencies
    │   ├── ModSettings.swift  # modsettings.lsx: which mods load, in order
    │   ├── ModLibrary.swift   # .pak files in the Mods folder → mods
    │   ├── ModRules.swift     # requirement problems, dependency order
    │   ├── ModInstaller.swift # .pak and .zip installs
    │   └── GamePaths.swift    # ~/Documents/Larian Studios/Baldur's Gate 3
    └── Tests/                 # builds real .pak files in memory
```

## Build and test

```
xcodegen generate
xcodebuild -project Tadpole.xcodeproj -scheme Tadpole build
cd TadpoleCore && swift test
```

`./build_app.sh` makes a Release `dist/Tadpole.app`, signed with the
"Tadpole Self-Signed" certificate when it's in the Keychain.

## How BG3 mods work on macOS

- Mods are `.pak` files in `~/Documents/Larian Studios/Baldur's Gate 3/Mods`.
- The game loads the mods listed in
  `PlayerProfiles/Public/modsettings.lsx`, in order, after its own base
  modules (GustavDev, GustavX). A `.pak` that isn't listed isn't loaded,
  unless it has no `meta.lsx` (an override), which always loads.
- Each mod's `.pak` holds `Mods/<Folder>/meta.lsx` with its UUID, name,
  version (packed into one 64-bit number) and dependencies.
- The game rewrites `modsettings.lsx` when it quits, so the load order is
  only changed while it isn't running.
- Norbyte's Script Extender (BG3SE) is Windows-only; mods shipping
  `ScriptExtender/` files are flagged.

## Testing without the game

`TADPOLE_BG3_DOCUMENTS=/some/folder` points the app at another folder
instead of the real Documents one, so you can try it on a copy or a made-up
setup without touching your game.

## Releasing updates (Sparkle)

The app updates itself with [Sparkle](https://sparkle-project.org): it reads
`appcast.xml` from this repo's main branch, shows the release notes embedded
in it, downloads the zip from GitHub Releases, and checks its signature
against `SUPublicEDKey` in `project.yml`.

Tadpole has its own keys, separate from Starseed's, so either app can be
released without the other:

- **Sparkle key**: in the maintainer's login Keychain, account `tadpole`.
  Back it up with `generate_keys --account tadpole -x tadpole-key.txt`
  (`generate_keys` is in `~/Library/Caches/Tadpole/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin`)
  and keep that file private. Without it, existing users can't receive
  updates.
- **Code signing**: the "Tadpole Self-Signed" certificate
  (`./make_signing_identity.sh` makes it once). The same certificate from
  build to build keeps the app's identity, so macOS asks for Keychain access
  (the Nexus API key) once. Back it up from Keychain Access → My
  Certificates → Export…

To release:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
   (Sparkle compares the build number), run `xcodegen generate`.
2. Write `release-notes/<version>.md`: it's the changelog users see in the
   update window, and the GitHub release's text.
3. Commit, then `./release.sh`.

To try an update before publishing: build and keep the current version,
bump the version, then `./release.sh --local http://127.0.0.1:8765/`, serve
`releases/v<version>` (`python3 -m http.server 8765 --directory releases/v<version>`)
and run the older app with `TADPOLE_FEED_URL=http://127.0.0.1:8765/appcast.xml`.
**Check for Updates…** shows the notes, installs and relaunches.
