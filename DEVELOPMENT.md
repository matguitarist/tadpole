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

`./build_app.sh` makes a Release `dist/Tadpole.app`, signed with a
self-signed certificate when the Keychain has one ("Tadpole Self-Signed",
or Starseed's), so macOS asks for Keychain access once.

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
