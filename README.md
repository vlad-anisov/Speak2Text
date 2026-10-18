# Speak2Text

Local push-to-talk dictation for macOS. Press a hotkey, speak, press it again (or hold it and release): the text is typed into the app you were using. Speech recognition runs fully on-device with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML), with live partial results so the final text appears about a second after you stop talking. Menu bar app, no Dock icon: click the icon to open the settings.

Requires macOS 14+ on Apple Silicon.

## Install

1. Build it (see below) or download `Speak2Text-<version>.zip` from the releases page and move `Speak2Text.app` to `~/Applications`.
2. Launch it and grant the permissions on the Permissions tab that opens on first run.
3. The first model load compiles Core ML for the Neural Engine and takes up to ~3 minutes. Later launches take a few seconds. Do not quit the app meanwhile.

## Build

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

Releases: `scripts/release.sh <version>` builds, zips into `dist/` and generates a signed Sparkle `appcast.xml`. It publishes nothing; upload the files to a GitHub release yourself. Signing keys come from Sparkle `generate_keys` (private key in your Keychain, public key in `Info.plist` as `SUPublicEDKey`).

## Permissions

- **Microphone** to record speech.
- **Input Monitoring** to see the global hotkey.
- **Accessibility** to paste the text (Cmd+V) into the active app.

The Permissions tab shows the status of each and opens the right System Settings pane. Text is delivered via the clipboard and the previous clipboard contents are restored right after pasting.

## Settings

Click the menu bar icon to open the settings (right-click for Settings / Quit).

- **General**: hotkey (click the key chip and press any key, left/right modifier or combo; default right Option; Esc cancels, ⓧ resets), mode (press to start/stop, default, Esc cancels; or hold to talk), language (ru / en / auto), mute other sounds while recording (to 0, restored afterwards, also after a crash), soft start/stop sounds (on by default), overlay, launch at login.
- **Model**: one model, Whisper large-v3 turbo 632 MB (downloaded on demand, with progress), accelerator (Neural Engine / GPU / CPU).
- **Dictionary**: replacements and filler words to remove.
- **History**: every dictation is saved with its audio (16 kHz mono wav) in `~/Library/Application Support/Speak2Text/History/`, including empty results. Search, copy, play, paste again, re-transcribe, show in Finder, delete. Keep forever / 30 / 7 / 1 day (default 30), or turn it off.
- **Permissions**: status of each permission.
- **About**: version, update check (Sparkle), GitHub link, log.

![General](docs/screenshots/settings-general.png)
![History](docs/screenshots/settings-history.png)

The start sound is played before muting and the microphone is ignored while it sounds (about 0.16 s), so the sound never reaches the transcription. Regenerate the sounds with `python3 scripts/make_sounds.py`.

Logs: `~/Library/Logs/Speak2Text/speak2text.log`.
