# Speak2Text

Local push-to-talk dictation for macOS. Hold a hotkey, speak, release: the text is typed into the app you were using. Speech recognition runs fully on-device with [WhisperKit](https://github.com/argmaxinc/WhisperKit) (Core ML), with live partial results so the final text appears about a second after you stop talking. Menu bar app, no Dock icon.

Requires macOS 14+ on Apple Silicon.

## Install

1. Build it (see below) or download `Speak2Text-<version>.zip` from the releases page and move `Speak2Text.app` to `~/Applications`.
2. Launch it and grant the permissions in the first-run window.
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

The permissions window shows the status of each and opens the right System Settings pane. Text is delivered via the clipboard and the previous clipboard contents are restored right after pasting.

## Settings

- **General**: hotkey (any key, left/right modifiers, combos; default right Option), mode (hold or toggle; Esc cancels), language (ru / en / auto), mute system audio while recording (with restore, also after a crash), overlay, sounds, launch at login.
- **Model**: Whisper model (download on demand), accelerator (Neural Engine / GPU / CPU), speed test.
- **Dictionary**: replacements, filler words to remove, and terms passed to the model as a prompt.
- **About**: version and update check (Sparkle).

Logs: `~/Library/Logs/Speak2Text/speak2text.log`.
