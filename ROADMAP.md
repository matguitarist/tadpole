# Roadmap

What's next for Tadpole, roughly in order. Bugs come first: they're things
that work today but can go wrong. Version numbers are targets, not promises.

Current version: **0.1** ([released](https://github.com/matguitarist/tadpole/releases/tag/v0.1)).

## Left over from 0.1

- [x] Create the GitHub repository (`matguitarist/tadpole`), push, and run
      `./release.sh`: Sparkle's feed and the downloads live there.
- [x] App icon (`design/AppIcon.swift`, `design/make_icons.sh`).
- [ ] End-to-end test with a real mod: install it from Nexus with a free
      account, launch the game, check it's loaded, quit, and check the game
      kept it in `modsettings.lsx`.
- [x] README: what Tadpole does, installing it (the "Open Anyway" step),
      screenshots.
- [x] Back up the Sparkle key (`generate_keys --account tadpole -x …`).
- [ ] Back up the "Tadpole Self-Signed" certificate (Keychain Access → Export…).

## Known bugs

- [x] **The load order goes stale when the game changes it.** The game rewrites
      `modsettings.lsx` when it quits (and can drop mods it couldn't load), but
      Tadpole only rereads it on ⌘R. Reload when the game quits
      (`NSWorkspace.didTerminateApplicationNotification`) and when Tadpole
      comes back to the front.
- [x] **Two copies of the same mod hide one of them.** Two .pak files with the
      same UUID (e.g. an update with a different file name) show as one row;
      the other is invisible and can't be removed from the app. Show
      duplicates with a "Keep Newest" fix.
- [x] **Installing while the game runs leaves new mods off.** The .pak is
      copied, but turning it on is refused (correctly), and nothing turns it on
      later. Remember the mods to turn on and do it once the game quits.
- [x] **Premium collection installs download everything at once.** A big
      collection starts dozens of downloads together, which can hit Nexus's
      rate limit. Download a few at a time.
- [x] **The install spinner stops too early** when several installs overlap
      (one shared `isInstalling` flag). Count running installs instead.
- [x] **Mods installed from files show as missing in collections and on Nexus
      pages.** Tadpole only knows the Nexus origin of mods it downloaded; the
      others can now be linked by hand (**Find on Nexus…**).
- [x] Downloads can't be cancelled. (The list is still lost when the app quits.)
- [ ] Script Extender detection is a guess (a `ScriptExtender/` folder inside
      the .pak). Also check the `meta.lsx` requirements and the Nexus
      requirements list.
- [ ] Multi-part .pak files (`_1.pak`, `_2.pak`) can't be read.

## 0.2: Keeping mods up to date

- [x] **Link installed mods to Nexus**: downloads are linked automatically;
      **Find on Nexus…** searches by name or takes a pasted link.
- [x] **Optional files for installed mods**: the details panel lists the
      mod's Nexus files by category (main, optional, miscellaneous), with
      **Install** for the ones you don't have.
- [ ] **Updates page**: compare installed mods with their latest Nexus
      version (needs the Nexus origin, see above), with **Update** and
      **Update All**, and the mod's changelog from Nexus.
- [ ] **Requirements from Nexus**: list a mod's required mods from its Nexus
      page and offer to install the missing ones in the same step.
- [ ] Notification when updates are found (checked at launch and every few
      hours, like Starseed).
- [ ] Download progress and errors in a status bar at the bottom of every page.

## 0.3: Profiles and saves

- [ ] **Profiles**: named load orders to switch between (e.g. one per
      playthrough). Installing a collection can make a profile.
- [ ] **Which mods a save uses**: read the save's `meta.lsf` (Larian's binary
      LSF format) and show the mods it was made with, flagging missing ones.
      **Load this save's mods** switches the load order to match.
- [ ] Back up saves automatically before **Play** when the mods changed since
      the last game.
- [ ] **Import and export load orders**: share a list with friends, and read
      BG3 Mod Manager's JSON export.

## Later

- [ ] Coexistence with the game's own mod manager (mod.io, since Patch 7):
      check that mods it installs show up correctly, and that Tadpole and the
      game don't undo each other's changes.
- [ ] Mod pictures from Nexus in the load order and the details panel.
- [ ] Filter the load order by name or author; undo (⌘Z) for load-order
      changes.
- [ ] Catch "Mod Manager Download" clicks from Safari or Chrome (the `nxm:`
      link), sharing them with Starseed: each app passes on links for the
      other game.
- [ ] Endorse and track mods on Nexus.
- [ ] Setup assistant on first launch (game check, Nexus key).
- [ ] Shared package with Starseed for the Nexus client, downloads and
      Sparkle setup, instead of copies.
- [ ] More translations.

## Done

- 0.1: load order, enable/disable, requirement warnings, Script Extender
  badges; install .pak and .zip/.7z/.rar; Nexus browsing, collections and
  downloads (free and Premium); saves with backups; Help, Settings, menus;
  Sparkle updates with Tadpole's own keys.
