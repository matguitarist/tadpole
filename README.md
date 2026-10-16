# Tadpole

[![Tests](https://github.com/matguitarist/tadpole/actions/workflows/tests.yml/badge.svg)](https://github.com/matguitarist/tadpole/actions/workflows/tests.yml)

*A mod manager for Baldur's Gate 3 on macOS.*

Install, order and keep track of your Baldur's Gate 3 mods on a Mac: browse
Nexus Mods and install mods and collections in the app, turn mods on and off,
set the load order, and back up your saves.

**[Download Tadpole for Mac](https://github.com/matguitarist/tadpole/releases/latest/download/Tadpole.dmg)**
(macOS 14 Sonoma or later)

![Browsing Baldur's Gate 3 mods on Nexus in Tadpole](docs/screenshots/browse.png)

## Install

1. Open the disk image and drag **Tadpole** onto **Applications**.
2. The first time, macOS says it can't check Tadpole, because it isn't signed
   with a paid Apple Developer ID. Open **System Settings → Privacy &
   Security**, scroll down, and click **Open Anyway**. This is needed only
   once: Tadpole updates itself after that.

## Getting started

1. Run Baldur's Gate 3 once and reach the main menu: the game creates the
   folders Tadpole works with.
2. To download mods in the app, add your personal Nexus Mods API key in
   **Settings → Nexus Mods** (⌘,). Browsing works without it.
   - *Premium* accounts download directly.
   - *Free* accounts click **Slow download** once per mod on the Nexus page
     that opens in Tadpole, and the mod installs itself.
3. Pick your mods, then press **Play**.

Everything is explained in **Help → Tadpole Help** (⌘?).

## What it does

- **Load order.** Lists the mods in `Documents/Larian Studios/Baldur's Gate
  3/Mods`, reading each `.pak` for its name, author, version and
  requirements. Turn mods on and off and drag them into order: Tadpole edits
  `modsettings.lsx`, the file the game reads, and keeps the previous one as
  `modsettings.lsx.bak`.
- **Requirements.** Warns about requirements that are missing, turned off or
  loading too late, and puts them first with **Order by Requirements**.
- **Install.** Drop `.pak` files or `.zip`, `.7z` and `.rar` archives on the
  window. Mods installed twice are flagged, with **Keep Newest**.
- **Nexus Mods and collections.** Search mods, see their files, install
  them; browse collections, see which of their mods you have, install the
  rest.
- **Saves.** Your saves with the game's picture, your party and the
  difficulty; back them up as .zip files and restore them.
- **Plays nice with the game.** While Baldur's Gate 3 runs, Tadpole doesn't
  touch the load order (the game rewrites it when it quits); mods installed
  meanwhile are turned on once it quits.
- **Script Extender.** Many mods use Norbyte's Script Extender, which only
  exists for Windows. Tadpole marks them: they load on a Mac, but their
  scripted features don't work.

![Collections from Nexus Mods](docs/screenshots/collections.png)

![Saves with their party and difficulty](docs/screenshots/saves.png)

## Roadmap

See [ROADMAP.md](ROADMAP.md) for known bugs and what's planned next.

## Building

See [DEVELOPMENT.md](DEVELOPMENT.md).

Tadpole is free and open source (MIT license). It isn't affiliated with
Larian Studios or Nexus Mods.
