# Tadpole

*A mod manager for Baldur's Gate 3 on macOS.*

Tadpole keeps your Baldur's Gate 3 mods in order on a Mac: install mods from
Nexus Mods, turn them on and off, set the load order, and see what each mod
needs before you start the game.

> Early development. Not released yet.

## What it does

- Lists the mods in `Documents/Larian Studios/Baldur's Gate 3/Mods`, reading
  each `.pak` for its name, author, version and requirements.
- Turns mods on and off and sets the load order (drag to reorder) by editing
  `modsettings.lsx`, the file the game reads. The previous file is kept as
  `modsettings.lsx.bak`.
- Installs `.pak` files and the `.zip` archives Nexus Mods gives you: drop
  them on the window.
- Warns about requirements that are missing, turned off, or loading too late,
  and puts requirements first with **Order by Requirements**.
- Flags mods that use Norbyte's **Script Extender**, which is only available
  on Windows: their scripted features won't work on a Mac.
- Shows `.pak` files the game always loads (no mod description inside) and
  entries left in the load order after their file was removed.

## Requirements

- macOS 14 Sonoma or later.
- Baldur's Gate 3 for Mac, run at least once (the game creates its
  Documents folder then).

## Building

See [DEVELOPMENT.md](DEVELOPMENT.md).

Tadpole is free and open source (MIT license). It isn't affiliated with
Larian Studios or Nexus Mods.
