# App Icons

The icons currently in the repo are **placeholders**. They are generated art, sized
correctly and wired into the asset catalog so the app builds and shows an icon
immediately — they are meant to be replaced by hand.

Each placeholder prints its own pixel dimensions and its slot name, so it is obvious
at a glance which file belongs in which slot.

## Where they live

```
SmartPiP/Assets.xcassets/
├── Contents.json
└── AppIcon.appiconset/
    ├── Contents.json
    └── icon_*.png          (the 10 files below)
```

The target builds this set via `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, and
`SmartPiP/Info.plist` points at it with `CFBundleIconName`.

## Required slots

macOS expects five point sizes, each at `@1x` and `@2x` — ten files in total. Leaving
any of them empty makes Xcode warn on build.

| File | Slot (`size`) | Scale | Pixel dimensions |
| --- | --- | --- | --- |
| `icon_16x16.png` | 16x16 | 1x | 16 × 16 |
| `icon_16x16@2x.png` | 16x16 | 2x | 32 × 32 |
| `icon_32x32.png` | 32x32 | 1x | 32 × 32 |
| `icon_32x32@2x.png` | 32x32 | 2x | 64 × 64 |
| `icon_128x128.png` | 128x128 | 1x | 128 × 128 |
| `icon_128x128@2x.png` | 128x128 | 2x | 256 × 256 |
| `icon_256x256.png` | 256x256 | 1x | 256 × 256 |
| `icon_256x256@2x.png` | 256x256 | 2x | 512 × 512 |
| `icon_512x512.png` | 512x512 | 1x | 512 × 512 |
| `icon_512x512@2x.png` | 512x512 | 2x | 1024 × 1024 |

Note that three pixel sizes appear twice (32, 256, 512). The files are still distinct
slots and both copies must be present — that is why the placeholders print the slot
name as well as the pixel count.

## Regenerating

Everything above is produced by one committed script,
[`Scripts/generate-app-icons.swift`](Scripts/generate-app-icons.swift). It writes all ten
PNGs *and* `AppIcon.appiconset/Contents.json`, so the set can never drift out of sync
with the manifest.

Regenerate the placeholders:

```bash
swift Scripts/generate-app-icons.swift
```

## Swapping in real artwork

Export a single square master (1024 × 1024 PNG recommended), then downscale it into
every slot with the same script:

```bash
swift Scripts/generate-app-icons.swift --source path/to/icon.png
```

That overwrites all ten files and rewrites `Contents.json`. Nothing else needs to
change — the filenames and slot names stay identical, so the asset catalog, the Xcode
target and `Scripts/build-cli.sh` all keep working.

Options:

- `--source <image>` — downscale this image instead of drawing placeholders.
- `--output <dir>` — write to a different `.appiconset` directory.

## Note for Command Line Tools builds

Compiling the asset catalog needs `actool`, which ships with Xcode. `Scripts/build-cli.sh`
therefore builds an `AppIcon.icns` from these same PNGs using `iconutil` instead. This
works because the `AppIcon.appiconset` filenames are exactly the names `iconutil`
expects inside an `.iconset` folder — so if you rename any file, update that script too.
