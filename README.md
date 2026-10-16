# hue-memory

Paper → confirm → Obsidian vault files. Flutter, Android-first.

**One-liner:** Mark the page → shoot it → confirm meaning → files appear in your phone’s Obsidian vault.

## Paths

| Where | Path |
| --- | --- |
| WSL / this checkout | `/home/mitch/projects/hue-memory` |
| Windows (if synced) | `D:\source\repos\hue-memory` |
| Product brief (Project store) | `docs/obsidian-zettel-memory-journal.md` in the hue-memory Project Agent Store |

## Prerequisites

- Flutter SDK (stable). On this WSL machine it was installed at `~/sdk/flutter` — add to PATH:
  ```bash
  export PATH="$HOME/sdk/flutter/bin:$PATH"
  ```
- Android toolchain for device/emulator runs (`flutter doctor`).

## Run

```bash
cd /home/mitch/projects/hue-memory   # or D:\source\repos\hue-memory on Windows
flutter pub get
flutter test
flutter run                          # attach a device / emulator
```

## Memory hues

UI tokens live in `lib/theme/memory_hues.dart` and `AppTheme` (`lib/theme/app_theme.dart`).

- Paper ground `#F1F0EC`, ink `#1B2A4A`, accent teal `#2A6B66`, recall amber `#C4923A`
- **No** `ColorScheme.fromSeed` / purple Material drift
- Fonts: Fraunces (titles) + IBM Plex Sans / Mono via `google_fonts`

## Package map (slice 1)

| Area | Path |
| --- | --- |
| Symbol pack + routing | `lib/symbols/` |
| `VaultFs` + fake + daily path | `lib/vault/` |
| Markdown / Canvas / wikilinks | `lib/writers/` |
| OCR interface + mock | `lib/ocr/` |
| Camera stub | `lib/camera/` |
| Capture / confirm shells | `lib/ui/` |

Real SAF vault I/O and camera preview are intentionally stubbed — see TODOs in those files.

## Tests

```bash
flutter test
```

Covers symbol routing (ZK ○∼≡◇△·), daily-note Moment path expansion, markdown frontmatter, JSON Canvas shape, and Link-picker wikilinks.
