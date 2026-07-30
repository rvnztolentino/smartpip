# SmartPiP

A small always-on-top video player for macOS that gets out of your way instead of making
you drag it around. It plays local MOV and MP4 files in a borderless window that only ever
sits in a screen corner, and it can either dodge your cursor or go click-through so the app
underneath keeps working. Zero dependencies: everything it uses ships with macOS.

## Modes

One choice with three options, in both the Player menu and the menu bar item. Exactly one
is selected at all times, and picking the one already selected does nothing.

> The recordings below are placeholders. See [docs/media/README.md](docs/media/README.md)
> for what each one should show.

### Avoid Cursor (⌃⌥⌘A, the default)

As the cursor gets close, the player moves to the next corner clockwise. Always one
direction, so you can see where it is going before it goes, and it stays where it lands. A
corner the cursor is already in gets skipped.

![Avoid Cursor](docs/media/avoid-cursor.gif)

### Lock Player (⌃⌥⌘L)

The window becomes click-through and stays put. Clicks, scrolls and hovers pass straight to
whatever is underneath, and resting the cursor on the player fades it well down so you can
read through it. The menu bar item carries the lock indicator and stays clickable.

![Lock Player](docs/media/lock-player.gif)

### Normal Player (⌃⌥⌘N)

An ordinary always-on-top player, and the only mode you can interact with directly. It is
the only one with transport controls, and the only one you can drop a file onto, resize, or
drag. Dragging still only picks a corner: let go anywhere and it parks in the corner for
that quarter of the screen.

![Normal Player](docs/media/normal-player.gif)

## Tech stack

- Swift 5, AppKit, no third-party packages
- AVFoundation: an `AVPlayer` inside an `AVPlayerView`, for the native transport controls
  and hardware decode through VideoToolbox
- Carbon `RegisterEventHotKey` for the global shortcuts, which needs no permission prompt
- `UserDefaults` for remembered corner, mode and size
- macOS 14 or later, Apple silicon or Intel

## Setup

1. Clone the repo.

   ```bash
   git clone https://github.com/rvnztolentino/smartpip.git && cd smartpip
   ```

2. Install a toolchain. Either works:

   - Xcode 15 or later, for the project file.
   - Command Line Tools only, for the build script.

   ```bash
   xcode-select --install
   ```

3. Have a local `.mov` or `.mp4` to hand. If you have none, record a few seconds with
   QuickTime Player (File ▸ New Screen Recording).

There is nothing else to install, no packages to resolve and no accounts to create.

## How to run

With Xcode, open the project and press ⌘R:

```bash
open SmartPiP.xcodeproj
```

With only the Command Line Tools, build and launch the app bundle:

```bash
Scripts/build-cli.sh && open build/SmartPiP.app
```

Pass `release` for an optimised build. The script rebuilds `build/SmartPiP.app` from
scratch every run, so rerun it after any source change. Output goes to `build/`, which is
gitignored.

To watch log output, run the executable directly instead of using `open`:

```bash
build/SmartPiP.app/Contents/MacOS/SmartPiP
```

Open a file with ⌘O or by dropping it on the player. Quit with ⌘Q.

## Configuration

No environment variables, no keys, no services, and no privacy permissions. The app asks
for nothing before it runs.

Global shortcuts:

- `⌃⌥⌘N` Normal Player
- `⌃⌥⌘A` Avoid Cursor
- `⌃⌥⌘L` Lock Player
- `⌃⌥⌘C` move to the next corner

The menus carry the rest: Open…, Play/Pause, Cycle Corner, Animate Corner Moves, which
switches the corner transition between a slide and an instant snap, and Reset Settings. The
menu bar item is worth knowing about, because it keeps working when the player itself does
not: a locked player cannot be clicked at all.

![The menu bar item](docs/media/menu.png)

Menu items backed by a global shortcut show it in the title rather than as a key equivalent.
That is deliberate. The Carbon hot key consumes the combination before the menu system sees
it, so binding both would risk firing twice.

The player remembers its corner, its mode and its size, written the moment they change
rather than at quit, so a Force Quit loses nothing. State lives in `UserDefaults` under
`com.rvnztolentino.SmartPiP`. Reset Settings, at the foot of both menus, puts it back to
bottom right, Avoid, 480x270 and animated corner moves. The same thing from the shell,
with the app closed:

```bash
defaults delete com.rvnztolentino.SmartPiP
```

If a shortcut silently does nothing, another app has already claimed it. Console will show
a line like `SmartPiP: could not register ⌃⌥⌘L`; change the matching entry in
[`SmartPiP/Input/HotKeyCenter.swift`](SmartPiP/Input/HotKeyCenter.swift).

## Notes

- Local `.mov` and `.mp4` only. No streaming, no MKV, no third-party playback engine.
- The window has no free positioning. It sits in one of the four corners, flush against
  `NSScreen.visibleFrame`, so it respects the menu bar and the Dock.
- Avoid and Lock refuse dropped files and resizes outright rather than working only if you
  are quick. Both say so on the player and point at Normal Player or Open.
- Resizing keeps the video's proportions. How big is remembered between launches, what
  shape is not: an empty player is always 16:9, because there is no video to take
  proportions from until one is opened.
- Quit while locked and the player relaunches locked, click-through from the moment it
  appears. `⌃⌥⌘N` and the menu bar item both release it, so this is recoverable, but it is
  surprising the first time.
- The app icons are placeholders, generated by `Scripts/generate-app-icons.swift`. See
  [ICONS.md](ICONS.md) for every filename, its exact size and its slot.
- The build script cannot compile the asset catalog, since `actool` ships only with Xcode,
  so it builds an `AppIcon.icns` from the same PNGs with `iconutil`. The app looks and
  behaves the same either way.
- Builds from the script are ad hoc signed rather than notarised. That is fine locally,
  where nothing is quarantined, but Gatekeeper would object if you sent the app to someone
  else.
