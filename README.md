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

### Flutter SDK (WSL)

```bash
export PATH="$HOME/.local/bin:$HOME/sdk/flutter/bin:$PATH"
# already appended to ~/.bashrc on this machine
```

### Linux desktop build deps — run once (`sudo`)

Required for `flutter run -d linux` / `flutter build linux` (fixes CMake “unable to find Ninja” / missing `CMAKE_CXX_COMPILER` / GTK). Password prompt is expected:

```bash
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  liblzma-dev \
  mesa-utils
```

Then verify (no sudo):

```bash
export PATH="$HOME/.local/bin:$HOME/sdk/flutter/bin:$PATH"
flutter doctor -v
# Linux toolchain should show clang++, cmake, ninja, GTK 3.0
```

Android SDK is separate (needed for phone/emulator only, not Linux desktop).

## Run (slice 2 flow)

```bash
export PATH="$HOME/.local/bin:$HOME/sdk/flutter/bin:$PATH"
cd /home/mitch/projects/hue-memory
flutter pub get
flutter test
flutter run -d linux
# or, without a display: flutter build linux --debug
```

1. Home is capture — tap the **teal shutter** (loads `assets/sample_page.png`; no camera required on Linux).
2. Mock OCR assigns a symbol chip (default ∼ fleeting) + region overlays.
3. Edit title/body, optionally **Link** recent pages, tap **Commit**.
4. Writes into an in-memory `FakeVaultFs`: `captures/raw/{page_id}.png` + `.meaning.json` + routed `.md` / `.canvas` / Daily Note append.
5. Snackbar + “Last commit” path on the capture screen.

Switch the confirm chip to **△ visual** or **· daily-tasks** to exercise those writers.

## Memory hues

UI tokens: `lib/theme/memory_hues.dart` + `AppTheme`.

- Paper `#F1F0EC`, ink `#1B2A4A`, accent teal `#2A6B66`, recall amber `#C4923A`
- **No** `ColorScheme.fromSeed` / purple Material drift
- Fonts: Fraunces + IBM Plex Sans / Mono via `google_fonts`

## Package map

| Area | Path |
| --- | --- |
| Capture session / page id | `lib/capture/` |
| Commit pipeline + daily append | `lib/vault/commit_pipeline.dart`, `daily_tasks_appender.dart` |
| Sample capture | `lib/camera/sample_capture.dart`, `assets/sample_page.png` |
| Confirm + link picker | `lib/ui/confirm_shell.dart`, `link_picker_sheet.dart` |
| Symbol pack + routing | `lib/symbols/` |
| Writers | `lib/writers/` |

**Still TODO:** real Android camera, SAF `VaultFs`, Mistral OCR.

## Tests

```bash
flutter test
flutter analyze
```

Covers symbol routing, daily-note paths, writers, daily-tasks append, commit pipeline (`FakeVaultFs`), and shutter→confirm→commit widget flow.
