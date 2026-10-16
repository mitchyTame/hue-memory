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

### Android (phone / emulator)

On this WSL machine the Android SDK is installed at `~/Android/Sdk` (cmdline-tools; licenses accepted). Ensure:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$HOME/.local/bin:$HOME/sdk/flutter/bin:$ANDROID_HOME/platform-tools:$PATH"
flutter doctor   # Android toolchain should be ✓
```

**No device is attached yet.** Options:

1. **Physical phone (easiest for WSL):** enable Developer options → USB debugging, plug in, then from **Windows** use `usbipd` to attach the device into WSL (`usbipd bind/attach`), or copy the debug APK:
   ```bash
   cd /home/mitch/projects/hue-memory
   flutter build apk --debug
   # APK: build/app/outputs/flutter-apk/app-debug.apk
   # Copy to phone and install, or: adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```
2. **Emulator:** install system images + emulator via `sdkmanager` / Android Studio (heavy on WSL); often simpler to run Flutter from Windows once Studio is installed there.

```bash
flutter devices
flutter run -d <device_id>
```

## Run (slice 2 flow)

```bash
export PATH="$HOME/.local/bin:$HOME/sdk/flutter/bin:$PATH"
cd /home/mitch/projects/hue-memory
flutter pub get
flutter test
flutter run -d linux
# or, without a display: flutter build linux --debug
```

If CMake fails on `flutter/ephemeral/.plugin_symlinks/jni/linux` (broken symlink, often after a Docker build), regenerate host plugins:

```bash
# if ephemeral is root-owned: sudo chown -R "$USER:$USER" linux/flutter/ephemeral build
flutter clean
flutter pub get
flutter run -d linux
```

1. Home is capture — **teal shutter** = live camera on Android (sample page on desktop); **gallery** = pick a photo.
2. Mock OCR assigns a symbol chip (default ∼ fleeting) + region overlays.
3. Edit title/body, optionally **Link** recent pages, tap **Commit**.
4. Writes into a vault: desktop uses `LocalVaultFs` (default under app Documents `hue-memory-vault`); **Android** picks the real Obsidian folder via **SAF** (`SafVaultFs`, persistable `content://` tree URI). Writes: `captures/raw/…` + routed `.md` / `.canvas` / Daily Note.
5. Gear → choose vault folder (SAF on Android) or **Write test note**.

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
| Local vault (desktop) | `lib/vault/local_vault_fs.dart` — default `…/Documents/hue-memory-vault` |
| SAF vault (Android) | `lib/vault/saf_vault_fs.dart` + `saf` plugin — persistable tree URI |
| Vault settings | gear → choose folder (SAF on Android) / write test note |
| Live camera (Android) | `lib/camera/live_camera_shell.dart` — full-bleed viewfinder + meta-zone guide |
| Sample + file pick | desktop shutter = sample; gallery = hardened file pick |
| Confirm + link picker | `lib/ui/confirm_shell.dart`, `link_picker_sheet.dart` |
| Symbol pack + routing | `lib/symbols/` |
| Writers | `lib/writers/` |

### Mistral OCR (when?)

**Now (slice 4):** after capture → meaning pass. Default is still **mock**. Enable live under **Settings → OCR** (API key + consent + toggle), or set `MISTRAL_API_KEY` in the environment and flip the toggle/consent in the UI.

Flow: shutter/gallery → `ConfigurableOcrClient` → Mistral `POST /v1/ocr` (image data URL) → confirm → vault write.

**Still TODO:** offline OCR queue, secure key storage, YAML symbol packs, ink-ghost Canvas, printables / promote ritual.

## Tests

```bash
flutter test
flutter analyze
```

Covers symbol routing, daily-note paths, writers, daily-tasks append, commit pipeline (`FakeVaultFs`), and shutter→confirm→commit widget flow.
