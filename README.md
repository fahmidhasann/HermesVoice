# HermesVoice

A macOS menu-bar app that puts your **Hermes agent** one hotkey away from
anywhere. Press **⌃⇧H**, talk or type, watch the reply stream in, then dismiss
and get back to work.

HermesVoice is a pure **client**. It talks to a **Hermes Agent Gateway** — a
separate OpenAI-compatible REST + SSE backend that you run and that holds your
API key. The gateway is not bundled here; you bring your own.

## Requirements

- macOS 14 (Sonoma) or later.
- A running **Hermes Agent Gateway** and its **API key** (`API_SERVER_KEY`).
  Point HermesVoice at the gateway's base URL (default `http://127.0.0.1:8642`
  for a local gateway). _Where to get / run a gateway: TODO — link the gateway
  project here._

## Install

1. Download `HermesVoice-<version>.dmg` and open it.
2. Drag **HermesVoice** onto the **Applications** folder.
3. Eject the disk image.

### First launch (unsigned app)

HermesVoice is **ad-hoc-signed**, not notarized (it ships free, with no paid
Apple Developer account). The first launch needs one extra step to get past
Gatekeeper:

- **Right-click** (or Control-click) **HermesVoice** in Applications ▸ **Open** ▸
  **Open**. You only do this once; afterwards it launches normally.
- If macOS only offers **Move to Trash** (no Open button), clear the download
  quarantine flag and try again:

  ```sh
  xattr -dr com.apple.quarantine /Applications/HermesVoice.app
  ```

This is expected for an unsigned app. The signature is valid — macOS just can't
attribute it to a known developer.

## First run

On first launch HermesVoice walks you through a short onboarding:

1. **Welcome.**
2. **Connect** — enter your **Gateway URL** (e.g. `http://127.0.0.1:8642`, or an
   `https://…` URL for a remote gateway) and your **API key**. Use **Test
   connection** to confirm. The key is stored in your **Keychain**, never in
   plaintext.
3. **Permissions** — grant microphone + speech recognition (transcription runs
   on-device).
4. **Hotkey** — press **⌃⇧H** anytime to toggle the panel.

You can skip the Connect step and finish later in **Settings ▸ Connection**.
Changing the URL or key there takes effect on your next message — no restart.

No API key? A no-auth local gateway works with the key left empty.

## Build from source

Requires the Swift toolchain (Xcode or Command Line Tools). There is no Xcode
project — this is a Swift Package.

```sh
./build-app.sh          # compile, assemble HermesVoice.app, embed icon, ad-hoc-sign
./make-dmg.sh           # the above, then package build/HermesVoice-<version>.dmg
swift run HermesVoiceTests   # run the unit-test suite
```

`make-dmg.sh` uses [`create-dmg`](https://github.com/create-dmg/create-dmg)
(`brew install create-dmg`) for a drag-to-Applications window when it's
installed, and falls back to plain `hdiutil` otherwise — no dependency required.

## Notes

- **Unsigned / un-notarized** by design. Notarization (a Developer ID and a paid
  account) can be added later without changing how the app works.
- **Microphone/speech permission may re-prompt after an update.** macOS keys
  those grants to the signing identity; an ad-hoc signature can differ between
  builds, so a new version may ask for microphone access again.
- Your gateway URL lives in app settings; your API key lives in the Keychain.
  Neither is sent anywhere except to the gateway you configure.
