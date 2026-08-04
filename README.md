# SmartPiP

A small always-on-top video player for macOS that gets out of your way instead of making
you drag it around. It plays local MOV and MP4 files in a borderless window that only ever
sits in a screen corner, and it can dodge your cursor, tuck itself against the screen edge,
or go click-through so the app underneath keeps working. Zero dependencies: everything it
uses ships with macOS.

## Modes

One choice with four options, in both the Player menu and the menu bar item. Exactly one is
selected at all times, and picking the one already selected does nothing.

**Hold Option to take the player back.** For as long as the key is down, Lock, Peek and
Avoid all behave like a normal player: the transport controls appear, the window can be
dragged and resized, and clicks land on it instead of passing through. Nothing moves on its
own while you hold it, so the player stays where you are reaching for it. Let go and the
mode carries on. Nothing is toggled and nothing is remembered, so there is no state to get
stuck in.

### Normal Player (⌃⌥⌘N, the default)

An ordinary always-on-top player, and the only mode you can interact with directly. It is
the only one with transport controls, and the only one you can drop a file onto, resize,
drag, or collapse yourself. Dragging still only picks a corner: let go anywhere and it parks
in the corner for that quarter of the screen, and it is never tiled against a screen edge
the way macOS does with ordinary windows.

![Normal Player](docs/media/normal-player.gif)

#### Collapse to Edge

A small grey button sits in the player's top left corner, carrying the same symbol the menu
bar shows for Peek, because it puts the player exactly where Peek would. Click it, or pick
**Collapse to Edge** from either menu, and the player slides off the nearest side edge,
leaving a small grey tab behind. Click the tab and it slides back out.

It moves on a click and at no other time. Passing the cursor over the button, the tab or the
player does nothing at all.

Normal Player only. The other three each have their own idea of where the window belongs, so
the menu item is greyed out there, and switching away from a collapsed player brings it back
out first. Your choice is kept, so coming back to Normal Player collapses it again. Holding
Option does not lend collapsing out either, unlike everything else Normal Player can do.

### Lock Player (⌃⌥⌘L)

The window becomes click-through and stays put. Clicks, scrolls and hovers pass straight to
whatever is underneath, and resting the cursor on the player fades it well down so you can
read through it. The menu bar item carries the lock indicator and stays clickable.

Hold Option and it takes clicks again, at full opacity, for as long as you hold it.

![Lock Player](docs/media/lock-player.gif)

### Peek Player (⌃⌥⌘P)

The player tucks itself against the nearest screen edge when your cursor reaches it, leaving
the same small tab a collapsed normal player leaves. Move the cursor away and it slides back
out on its own after a moment.

The other half of Avoid: both get out of the way of the pointer, and the difference is only
where they go. Avoid takes the whole window to another corner and stays there; Peek slides
it aside and comes back once you have gone.

Going is immediate, because a player that waited would be in the way for exactly as long as
it waited. Coming back takes a moment, so crossing its corner on the way somewhere else does
not make it spring out at you. It moves when the cursor arrives or leaves, and at no other
time.

Hold Option and it comes out and stays out until you let go.

### Avoid Cursor (⌃⌥⌘A)

As the cursor gets close, the player moves to the next corner clockwise. Always one
direction, so you can see where it is going before it goes, and it stays where it lands. A
corner the cursor is already in gets skipped.

Hold Option and it stops dodging until you let go. On release it waits for the cursor to get
clear before it will run again, so letting go of the key does not undo the placing you held
it down to do.

![Avoid Cursor](docs/media/avoid-cursor.gif)

## Tech stack

- Swift 5, AppKit, no third-party packages
- AVFoundation: an `AVPlayer` inside an `AVPlayerView`, for the native transport controls
  and hardware decode through VideoToolbox
- Carbon `RegisterEventHotKey` for the global shortcuts, which needs no permission prompt
- A non-activating `NSPanel`, so a click on the player never steals focus from your work
- `NSEvent.modifierFlags`, polled on the same timer as the cursor, for the Option hold. A
  global event monitor would want the Input Monitoring permission for the same answer
- `UserDefaults` for the remembered corner, mode, size and collapse
- The window is moved by hand rather than by `performDrag(with:)`. The system's drag loop
  offers to tile a window that reaches a screen edge, and this one has four legal positions

## Requirements

**macOS 14 Sonoma or later.** That is the deployment target, set in both
`SmartPiP/Info.plist` and the project file, so the app will not launch on anything older.

Apple silicon and Intel are both supported when you build it yourself. Note that
`Scripts/build-cli.sh` compiles for the machine it runs on, so a build made on Apple
silicon is arm64 only. If you need one binary for both, build twice and join them with
`lipo`, or build from the Xcode project.

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

Clicking the player never brings SmartPiP to the front, so whatever you are working in keeps
the keyboard. That means ⌘O, ⌘Q and the space bar only reach the player while SmartPiP is
already the active app: click its Dock icon first, or use the menu bar item, which works
whatever is in front.

## Configuration

No environment variables, no keys, no services, and no privacy permissions. The app asks
for nothing before it runs.

Global shortcuts:

- `⌃⌥⌘N` Normal Player
- `⌃⌥⌘L` Lock Player
- `⌃⌥⌘P` Peek Player
- `⌃⌥⌘A` Avoid Cursor
- `⌃⌥⌘C` move to the next corner

Holding `⌥` on its own is the sixth control and the only one that is not a shortcut: it
applies while held rather than switching anything, so it has no menu item, only a note under
the modes in both menus. It has to be Option alone, since every shortcut above already
contains it.

The menus carry the rest: Open…, Play/Pause, Collapse to Edge, Cycle Corner, Animate Corner
Moves, which switches the corner transition between a slide and an instant snap, and Reset
Settings. The menu bar item is worth knowing about, because it keeps working when the player
itself does not: a locked player cannot be clicked at all, and a collapsed or peeking one is
a tab.

![The menu bar item](docs/media/menu.png)

Menu items backed by a global shortcut show it in the title rather than as a key equivalent.
That is deliberate. The Carbon hot key consumes the combination before the menu system sees
it, so binding both would risk firing twice.

The player remembers its corner, its mode, its size and whether you collapsed it, written
the moment they change rather than at quit, so a Force Quit loses nothing. A peeking player
tucking itself away is not remembered, because that is the cursor rather than you. State
lives in `UserDefaults` under `com.rvnztolentino.SmartPiP`. Reset Settings, at the foot of
both menus, puts it back to bottom right, Normal Player, 480x270, out from the edge and
animated corner moves. The same thing from the shell, with the app closed:

```bash
defaults delete com.rvnztolentino.SmartPiP
```

If a shortcut silently does nothing, another app has already claimed it. Console will show
a line like `SmartPiP: could not register ⌃⌥⌘L`; change the matching entry in
[`SmartPiP/Input/HotKeyCenter.swift`](SmartPiP/Input/HotKeyCenter.swift).

## Notes

- Local `.mov` and `.mp4` only. No streaming, no MKV, no third-party playback engine.
- The window has no free positioning. It sits in one of the four corners, flush against
  `NSScreen.visibleFrame`, so it respects the menu bar and the Dock. A player tucked against
  the edge is the one exception, and it rests beside the corner it came from.
- macOS never tiles the player. Dragging an ordinary window to a screen edge offers to
  resize it to half the display, which would put this one somewhere it is not allowed to be,
  so SmartPiP moves its own window and never hands the drag to the system.
- Clicking the player does not activate SmartPiP. Besides keeping your focus where it was,
  this is what makes the Option hold usable at all: macOS reserves ⌥ click on another app's
  window for "switch to it and hide the one I am in", so every grab of the player would
  otherwise have hidden whatever you were working in.
- Lock, Peek and Avoid refuse dropped files and resizes outright rather than working only if
  you are quick. All three say so on the player, and all three point at the Option hold,
  which is the shortest way through without giving up the mode you chose.
- A player at the edge cannot be dragged or resized either, in any mode. There is a tab's
  width of it on screen, so there is nothing to take hold of. Bring it out first.
- Resizing keeps the video's proportions. How big is remembered, what shape is not: an empty
  player is always 16:9, because there is no video to take proportions from until one is
  opened.
- Quit while locked and the player relaunches locked, click-through from the moment it
  appears. `⌃⌥⌘N`, holding Option, and the menu bar item all release it, so this is
  recoverable, but it is surprising the first time.
- Quit while collapsed in Normal Player and it relaunches as a tab at the screen edge. Click
  the tab, or use the menu bar item. Peek always relaunches out, and tucks itself away again
  only once your cursor arrives.
- The app icons are placeholders, generated by `Scripts/generate-app-icons.swift`. See
  [ICONS.md](ICONS.md) for every filename, its exact size and its slot.
- The build script cannot compile the asset catalog, since `actool` ships only with Xcode,
  so it builds an `AppIcon.icns` from the same PNGs with `iconutil`. The app looks and
  behaves the same either way.
- Builds from the script are ad hoc signed rather than notarised. That is fine locally,
  where nothing is quarantined, but Gatekeeper would object if you sent the app to someone
  else.
