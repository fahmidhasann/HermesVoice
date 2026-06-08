# Plan: Distribute HermesVoice as a DMG + make the gateway per-user

> Self-contained execution plan. A fresh session can start here with no prior
> context. Approved 2026-06-08.

## Starting context (read first)

HermesVoice is a macOS menu-bar voice client (Swift Package, **no Xcode
project**) for a **Hermes Agent Gateway** — a separate OpenAI-compatible
REST+SSE backend (likely Python; the client comments reference
`_normalize_multimodal_content`). The gateway is **not** in this repo.

Current build path: `./build-app.sh` compiles `swift build -c release`, assembles
`build/HermesVoice.app`, embeds the icon, stamps the version, and **ad-hoc-signs**
it (`codesign --sign -`). There is **no DMG and no notarization**. Bundle id
`com.hermes.voice`, min macOS 14.

How it talks to the gateway today:
- `Sources/HermesVoice/Config.swift` — singleton; loads `apiKey` **once at init**
  from `~/.hermes/.env` (`API_SERVER_KEY=...`, parsed by `APIKeyParser`). Also
  holds a compiled `http://127.0.0.1:8642` default.
- `Sources/HermesVoice/HermesAPIClient.swift` — `URLSession`; resolves the
  endpoint **per request** from `AppSettingsStore.loadCurrent()` (`:43`), but
  uses the captured `config.apiKey` for the `Authorization: Bearer` header
  (`:58`, `:140`). Endpoints: `/v1/chat/completions` (SSE), `/v1/health`,
  `/v1/models`.
- `Sources/HermesVoiceKit/AppSettings.swift` — `Codable` settings persisted as
  JSON in `UserDefaults` (key `hermesVoiceSettings`). Has `endpointHost`/
  `endpointPort` (default `127.0.0.1`/`8642`) and `baseURLString` that hardcodes
  `http://`. **Tolerant decoder** (`init(from:)`) defaults any missing field, so
  adding fields never wipes existing settings.
- `Sources/HermesVoice/AppSettingsStore.swift` — `ObservableObject`; persists on
  every change (`didSet`).
- `Sources/HermesVoice/SettingsView.swift` — `ConnectionSettingsTab` (~121-196)
  has Host/Port `TextField`s + a Model picker + a **Refresh models** button that
  probes the gateway (`client.fetchModels()`) and reports status.
- `Sources/HermesVoice/OnboardingView.swift` + `OnboardingWindowController.swift`
  — 3-step first-run flow (`enum Step { welcome, permissions, hotkey }`), gated
  by UserDefaults flag `hermesVoiceHasOnboarded`. **No credential step.**
- No Keychain wrapper exists anywhere.

**The two gaps** preventing other people from using it with their own gateway:
1. A fresh install has **no API key and no UI to enter one** (only `~/.hermes/.env`).
2. There is **no installer** (DMG) and no documented install path.

## Decisions (locked)
- Ship **unsigned/free** — no Apple Developer account; document the Gatekeeper
  bypass instead of notarizing.
- Collect credentials via **onboarding + Settings**, store the API key in
  **Keychain**.
- **Topology:** support both local and remote, **default to local**. Replace the
  Host+Port pair with one **Gateway URL** field (handles http/https/custom port
  in one input; also lifts the current http-only limit).
- **Do NOT bundle the gateway.** The app stays a pure client; users bring their
  own running gateway + API key.

---

## Part A — Per-user gateway configuration

### A1. Keychain credential store (new)
New `Sources/HermesVoice/CredentialsStore.swift` — small `Security`-framework
wrapper. Keep it in the **app target** (not `HermesVoiceKit`, which is meant to
stay hardware/system-free and unit-testable). Service `com.hermes.voice`,
account `api-server-key`; `get() / set(_:) / delete()` over `SecItem*`. Wrap in
a thin `ObservableObject` (published `apiKey`) so SwiftUI `SecureField`s bind and
writes hit Keychain immediately — same "edit → persist" feel as
`AppSettingsStore`.

### A2. Read the key live (not the startup snapshot)
- In `HermesAPIClient.swift` change the `Authorization` header at `:58` and
  `:140` to read the key from `CredentialsStore` **per request**, mirroring the
  per-call `AppSettingsStore.loadCurrent()` at `:43`. A key typed in Settings
  then works on the next request with no restart.
- In `Config.swift`, demote `loadAPIKey()` to a **one-time migration**: at launch,
  if Keychain has no key but `~/.hermes/.env` has one, import it into Keychain.
  Remove `apiKey` as the request-time source.

### A3. Gateway URL in the settings model
`Sources/HermesVoiceKit/AppSettings.swift`:
- Add `gatewayURL: String` (default `"http://127.0.0.1:8642"`).
- `baseURLString` returns the trimmed `gatewayURL` (strip trailing `/`).
- Migration: in `init(from:)`, when `gatewayURL` is absent but legacy
  `endpointHost`/`endpointPort` decode, compose `http://host:port`. Keep
  host/port decodable for one version; drive everything off `gatewayURL`.
- API key stays **out** of here (UserDefaults JSON is plaintext) — Keychain only.

### A4. Settings → Connection tab
`Sources/HermesVoice/SettingsView.swift` (`ConnectionSettingsTab`):
- Replace Host + Port `TextField`s with one **Gateway URL** field bound to
  `settings.gatewayURL`.
- Add a **SecureField "API key"** bound to the `CredentialsStore` wrapper
  (optional — empty allowed for no-auth local gateways).
- Keep the Model picker + **Refresh models** (doubles as connection test).
  Reword the caption to mention URL + key.

### A5. Onboarding "Connect" step
`Sources/HermesVoice/OnboardingView.swift` + `OnboardingWindowController.swift`:
- Insert a **Connect** step → order `welcome → connect → permissions → hotkey`.
- Fields: Gateway URL (pre-filled `http://127.0.0.1:8642`) + API key
  (SecureField) + a **Test connection** button using the existing
  `HermesAPIClient.checkHealth()` / `fetchModels()`, showing ✓/✗.
- Skippable (writes whatever's entered; finish later in Settings).

### A6. User-facing copy
`HermesAPIClient.swift` `HermesAPIError.errorDescription` (~196-210) + `.noAPIKey`
hardcode `~/.hermes/.env` and `127.0.0.1:8642`. Reword generically and point at
Settings ▸ Connection (e.g. "Authentication failed — check your API key in
Settings ▸ Connection"; "Can't reach the gateway — check the URL in
Settings ▸ Connection").

---

## Part B — DMG installer (unsigned / free)

### B1. Packaging script (new) — `make-dmg.sh` at repo root
1. Run `./build-app.sh` (ad-hoc-signs + embeds icon/version).
2. Stage `build/HermesVoice.app` + a `/Applications` symlink in a temp dir.
3. `hdiutil create -volname HermesVoice -srcfolder <stage> -ov -format ULFO
   build/HermesVoice-<version>.dmg` (version from Info.plist, as build-app.sh
   already reads).
- App is ad-hoc-signed (valid signature, no Developer ID) → download shows
  "unidentified developer," **not** "damaged"; right-click→Open works.
- Optional: if `create-dmg` (Homebrew) is present, use it for a drag-to-
  Applications background; otherwise plain `hdiutil` is fully functional. Keep
  dependency-light.

### B2. Install instructions (new `README.md`)
- Drag **HermesVoice** → **Applications**.
- First launch: **right-click → Open → Open** once; if macOS only offers "Move to
  Trash", run `xattr -dr com.apple.quarantine /Applications/HermesVoice.app` then
  open.
- On first run, complete onboarding: paste **Gateway URL** + **API key**.
- Link to how to run/obtain a Hermes Agent Gateway + its `API_SERVER_KEY`
  (placeholder — gateway lives outside this repo).

### B3. Caveats to note (not blockers)
- Unsigned/un-notarized → bypass step required (accepted trade-off). Notarization
  can be added later (needs $99/yr account) without touching Part A.
- Mic/Speech TCC grants are keyed to the signing identity; an ad-hoc signature
  can change per build, so a future update may re-prompt for mic access.

---

## Critical files
- **New:** `Sources/HermesVoice/CredentialsStore.swift`, `make-dmg.sh`, `README.md`
- **Edit:** `Sources/HermesVoice/Config.swift` (key→migration only),
  `Sources/HermesVoice/HermesAPIClient.swift` (live key read + error copy),
  `Sources/HermesVoiceKit/AppSettings.swift` (`gatewayURL` + migration),
  `Sources/HermesVoice/SettingsView.swift` (Connection tab),
  `Sources/HermesVoice/OnboardingView.swift` + `OnboardingWindowController.swift`
- **Tests:** `Tests/HermesVoiceTests/` — `gatewayURL` default, `baseURLString`
  derivation, host/port→URL migration (extend existing tolerant-decode tests).

## Verification
1. `./build-app.sh && open build/HermesVoice.app`.
2. Fresh-install sim: `defaults delete com.hermes.voice`; delete the Keychain item
   (`security delete-generic-password -s com.hermes.voice`); clear
   `hermesVoiceHasOnboarded`; relaunch → onboarding shows **Connect** with empty key.
3. Enter URL + key, **Test connection** → models load; send a message → streams.
   Change URL in Settings → next request uses it, no restart.
4. Point at an `https://` gateway → confirms the http-only limit is gone.
5. `./make-dmg.sh` → mount `build/HermesVoice-*.dmg`, drag to Applications;
   simulate quarantine
   (`xattr -w com.apple.quarantine "0000;0;HermesVoice;" /Applications/HermesVoice.app`)
   and verify the bypass instructions clear it.
6. `swift test`; then `graphify update .`.

## Out of scope
Bundling the gateway backend; Apple notarization & Developer ID signing;
auto-update (Sparkle). All layer on later without reworking Part A.

## Design constraints (from CLAUDE.md / DESIGN.md)
New UI (Connect step, API key field) must use `Theme.swift` tokens — no raw
values; one accent (Terracotta), type ceiling 15px, WCAG AA, honor reduce-motion.
Match the existing Settings/onboarding idioms.
