<div align="center">

<img src="docs/icons/icon.png" width="128" alt="Speak2Text icon">

# Speak2Text

**Local push-to-talk dictation for macOS. Press a key, speak, get text.**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-lightgrey)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/vlad-anisov/Speak2Text)](https://github.com/vlad-anisov/Speak2Text/releases/latest)

<img src="docs/screenshots/settings-general.png" width="640" alt="Speak2Text settings">

<img src="docs/screenshots/overlay-listening.png" height="60" alt="Overlay while listening">
&nbsp;
<img src="docs/screenshots/overlay-done.png" height="60" alt="Overlay when done">

</div>

Press a hotkey, speak, press it again (or hold it and release): the text is typed into the app you were using. Recognition runs fully on your Mac with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML). Speak2Text is a menu bar app with no Dock icon; click the icon to open the settings.

## Features

- On-device [WhisperKit](https://github.com/argmaxinc/WhisperKit) turbo model (large-v3 turbo, 632 MB) on the Neural Engine
- Live mode: partial results while you talk, final text about 1 s after you stop
- Any hotkey (single left/right modifier, any key, or a combo), toggle or hold-to-talk mode
- Animated pill overlay showing the state
- Mutes other audio while recording and restores it afterwards
- Built-in fixes for English tech terms that Whisper writes in Cyrillic (GitHub, pipeline, Jira, ...) and optional filler-word removal
- History with saved audio, search, copy, paste again and re-transcribe
- Auto-updates via [Sparkle](https://sparkle-project.org)
- English and Russian UI (follows macOS); all Whisper languages for recognition

## Install

1. Download `Speak2Text-<version>.dmg` from [Releases](https://github.com/vlad-anisov/Speak2Text/releases/latest), open it and drag `Speak2Text.app` onto the Applications folder.
2. **First launch.** The app is signed with a development certificate and is **not notarized**, so macOS will block it the first time. Do one of:
   - Right-click `Speak2Text.app` and choose **Open**, then confirm; or
   - open **System Settings → Privacy & Security** and click **Open Anyway**; or
   - run in Terminal:
     ```sh
     xattr -dr com.apple.quarantine /Applications/Speak2Text.app
     ```
3. Grant the permissions in the "Permissions needed" block at the top of General (Settings open there on first run; the block disappears once everything is granted):
   - **Microphone** to record speech
   - **Input Monitoring** to see the global hotkey
   - **Accessibility** to paste the text (Cmd+V) into the active app
4. Wait for the model (status under Accelerator). The first launch downloads it and compiles Core ML for the Neural Engine, which takes a few minutes (up to ~3 minutes for the compile). Later launches take a few seconds. Do not quit the app meanwhile.

Requires macOS 14+ on Apple Silicon.

## Usage

- The default hotkey is **Right Option**. Change it in Settings → General: click the key chip and press any key, modifier or combo (Esc cancels, ⓧ resets).
- Default mode is **Press**: press to start, press again to stop (Esc cancels). Switch to **Hold** to talk only while the key is down.
- Language: "Same as system" (default, falls back to auto-detect for unsupported languages), "Auto-detect" or any Whisper language. Start/stop sounds, overlay, filler-word removal and launch at login are in Settings → General.
- Right-click the menu bar icon for Settings and Quit.
- Text is delivered through the clipboard (Cmd+V) and your previous clipboard contents are restored right after pasting.
- In tests the final text appeared about 0.6-1.05 s after stop.
- History is stored in `~/Library/Application Support/Speak2Text/History/` (audio as 16 kHz mono wav); keep it forever, 30 days (default), 7, 1, or turn it off.
- Log: `~/Library/Logs/Speak2Text/speak2text.log`.

<p align="center">
<img src="docs/screenshots/settings-history.png" width="560" alt="History">
</p>

## Privacy

Nothing leaves your Mac. Speech recognition, history and settings are all local. The model is downloaded once from Hugging Face by WhisperKit; the only other network use is Sparkle checking for updates.

## Build from source

Only the Xcode Command Line Tools are needed (Swift 6.1+).

```sh
./build.sh                 # builds, signs and installs ~/Applications/Speak2Text.app
S2T_NO_INSTALL=1 ./build.sh  # build only, into build/
S2T_IDENTITY="Developer ID Application: ..." ./build.sh   # custom signing identity
```

Test recognition without a microphone:

```sh
Speak2Text --file sample.wav     # prints the text and final_wait (delay after the end of audio)
```

Regenerate the start/stop sounds with `python3 scripts/make_sounds.py`. See [docs/SPEC.md](docs/SPEC.md) for the detailed spec.

## Releasing

`scripts/release.sh <version>` builds, zips into `dist/`, generates a signed Sparkle `appcast.xml` and a drag-to-Applications `Speak2Text-<version>.dmg` (via [dmgbuild](https://github.com/dmgbuild/dmgbuild), installed into a venv under `.build/`). It publishes nothing: create the release `v<version>` on GitHub and attach the `.dmg` (for people), the `.zip` (for Sparkle updates) and `dist/appcast.xml`. Signing keys come from Sparkle `generate_keys` (private key in your Keychain, public key in `Info.plist` as `SUPublicEDKey`).

## Credits

- [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax: on-device speech recognition
- [Sparkle](https://sparkle-project.org): auto-updates
- [OpenAI Whisper](https://github.com/openai/whisper) models

## License

[MIT](LICENSE) © 2026 Uladzislau Anisau
