# hue-memory

Paper → confirm → Obsidian vault files. Flutter, Android-first.

**One-liner:** Mark the page → shoot it → confirm meaning → files appear in your phone’s Obsidian vault.

## Paths

| Where | Path |
| --- | --- |
| Home (mgtroaming) | `/home/mgtroaming/Projects/hue-memory` |
| Mitch-Dev (WSL) | `/home/mitch/projects/hue-memory` |
| Remote | `https://github.com/mitchyTame/hue-memory` |
| Product brief | Project store `docs/obsidian-zettel-memory-journal.md` |

## Prerequisites

### Flutter + Android toolchain (mgtroaming)

Already on `~/.bashrc` (open a new shell):

```bash
# JAVA_HOME → ~/.local/share/jdk/jdk-17…
# Flutter   → ~/.local/share/flutter/bin
# Android   → ~/Android/Sdk (platform-tools + cmdline-tools)
flutter doctor
adb version
```

### Wireless debugging (phone over Wi‑Fi)

PC side is ready (`adb` on PATH). On the phone (Android 11+):

1. **Settings → Developer options → Wireless debugging** → On  
2. Tap **Pair device with pairing code** — note **IP:pairing-port** and the **6-digit code**  
3. On this PC:

```bash
adb pair <PHONE_IP>:<PAIRING_PORT>
# enter the pairing code when prompted
adb connect <PHONE_IP>:<DEBUG_PORT>
# DEBUG_PORT is shown on the Wireless debugging main screen (not the pairing port)
adb devices
flutter devices
flutter run -d <device_id>
```

Same Wi‑Fi for phone + PC. Re-connect after sleep with `adb connect IP:port` (pairing only once until revoked).

### Linux desktop build deps (optional)

Needs `ninja`, GTK, etc. for `flutter run -d linux`. Android phone path does not require them.

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
| Symbol pack + routing | `lib/symbols/` — YAML packs + Dart fallback |
| Writers | `lib/writers/` |

### Mistral OCR

After capture → meaning pass. Default **mock**. Enable live: **Settings → OCR** (API key + consent + toggle), or `MISTRAL_API_KEY` env.

### Symbol packs (YAML)

Packs live in `assets/packs/*.yaml` (ZK + GTD). **Settings → Symbols** switches the active pack; a copy is mirrored to `symbol-journal/packs/active.yaml` in the vault. Dart `DefaultPacks` remains a fallback if assets fail.

**Still TODO:** offline OCR queue, full 18-glyph library editor.

### Ink-ghost Canvas

△ / visual commits write JSON Canvas with the page photo as a **file node under** text nodes (bbox-scaled). Confirm shows an **Ink ghost** toggle (dimmed photo + region cards). `meaning.json` records `ink_ghost`.

### Paper kit (printables)

**Settings → Paper kit** writes A6 PDFs into `symbol-journal/printables/`:

- Ink legend for the active pack
- Hue-dot sticker sheet (twin 2-char codes, Memory hues)

### Promote ritual

Capture-home **recall** icon (or Settings → Promote ritual): list `fleeting/` notes, rewrite in own words (gate), write `permanent/` with wikilink back, stamp fleeting `status: promoted`.

### Thread tick `›`

Meta-zone chevron (or confirm **Thread › from last**) pre-checks the previous session page as a wikilink. Picker can still clear/merge. `meaning.json` records `thread_tick`.

### OCR API key

Stored via platform **secure store** (migrates any legacy SharedPreferences copy on read).

## Tests

```bash
flutter test
flutter analyze
```

Covers symbol routing, daily-note paths, writers, daily-tasks append, commit pipeline (`FakeVaultFs`), and shutter→confirm→commit widget flow.
