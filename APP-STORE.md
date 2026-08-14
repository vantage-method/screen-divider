# Shipping Screen Divider to the Mac App Store

Pricing model: auto-renewable subscription — **$0.99/month** or **$5.99/year**,
both with a 7-day free trial. Either product unlocks the app.

The code side is done: StoreKit 2 (`SubscriptionManager` + paywall window),
App Sandbox entitlements, `SMAppService` login item, and an XcodeGen spec.
What remains is account setup, App Store Connect configuration, and the
archive/upload — steps below in order.

## 1. One-time prerequisites

- [ ] **Apple Developer Program** ($99/yr) — enroll at
      https://developer.apple.com/programs/enroll/ as Harvey Creative (org
      enrollment needs a D-U-N-S number; individual enrollment is faster and
      fine — the seller name on the store is just your name in that case).
- [ ] **Paid Applications agreement** — in App Store Connect →
      Business, accept the Paid Apps agreement and complete banking + tax
      forms. Subscriptions cannot go live without this. Do it first; approval
      can take a day or two.
- [ ] **Install Xcode** from the App Store. This iMac (macOS 13.7) maxes out
      at **Xcode 15.2** — download from
      https://developer.apple.com/download/all/ (the App Store may refuse on
      Ventura). Verified 2026-08: Apple's minimum-SDK upload mandate (Xcode 26
      as of April 2026) applies to iOS/iPadOS/tvOS/visionOS/watchOS only, NOT
      macOS — Xcode 15.2 can still upload Mac apps. If Apple ever extends the
      mandate to macOS, build from a machine on a newer macOS instead.
      After install: `sudo xcode-select -s /Applications/Xcode.app`
- [ ] `brew install xcodegen`

## 2. Host the privacy policy

The paywall links to `https://harveycreative.co/screendivider/privacy.html`
(see `PaywallWindowController.privacyPolicyURL`). Apple requires this URL to
be live at review time, and it also goes in the App Store listing.

Add the page to the agency-site repo (remember: build via `node build.mjs`
and commit `dist/`). Content: the app collects no data, everything stays on
device, payments handled by Apple. Terms of Use link uses Apple's standard
EULA, which is fine for subscriptions.

## 3. App Store Connect setup

1. Certificates/IDs are handled automatically by Xcode signing — just make
   sure you're signed into Xcode (Settings → Accounts) with the developer
   Apple ID, and put your Team ID into `project.yml` (`DEVELOPMENT_TEAM`).
2. App Store Connect → My Apps → **+ New App**:
   - Platform macOS, name **Screen Divider** (if taken, fallback ideas:
     "Screen Divider – Snap Zones", "Screen Divider Pro"),
   - Bundle ID `com.vantagemethod.screendivider`, SKU `screendivider`.
3. **Subscriptions** (App Store Connect → the app → Subscriptions):
   - Create group **Screen Divider Pro**.
   - Product 1: reference name `Monthly`, product ID
     `com.vantagemethod.screendivider.monthly`, duration 1 month,
     price **$0.99**.
   - Product 2: reference name `Yearly`, product ID
     `com.vantagemethod.screendivider.yearly`, duration 1 year,
     price **$5.99**.
   - On EACH product add an **Introductory Offer**: Free, 1 week, all
     territories. (The paywall reads this from StoreKit and renders
     "7 days free, then …" automatically — no code change.)
   - Product IDs must match `SubscriptionManager.swift` exactly.
4. **App price: Free** (the subscription is the only charge).
5. **App Privacy** questionnaire: "Data Not Collected" (the app has no
   analytics, no accounts, no network calls of its own).

## 4. Build and upload

```bash
cd "~/Claude Code Projects/personal/Screen Divider/ScreenDivider"
xcodegen generate
open ScreenDivider.xcodeproj
```

In Xcode:
1. Target → Signing & Capabilities: select the team; confirm App Sandbox +
   Outgoing Connections show up (they come from `ScreenDivider.entitlements`).
2. Optional but recommended: test purchases locally first — scheme → Run
   options → StoreKit Configuration → `ScreenDivider.storekit`, run, and
   buy with the fake store. (If Xcode complains about the .storekit file
   version, create a new StoreKit config file and re-add the two products.)
3. Product → **Archive** → Distribute App → **App Store Connect** → Upload.

## 5. Listing + review

- Screenshots: at least one, 1280×800 / 1440×900 / 2560×1600 / 2880×1800.
  Best shot: a dragged window with the zone overlay visible on a tidy desktop.
- Subtitle idea: "Custom snap zones for your windows". Keywords: window
  manager, snap, tiling, split screen, zones, productivity.
- **App Review notes** (important — this is what gets window managers
  approved): explain that the app uses the Accessibility API with explicit
  user consent to reposition windows the user drags, the same mechanism as
  other window managers on the store; there is no keylogging and no data
  collection. Mention the free trial so the reviewer can test.
- Review must be able to reach the paywall: it shows automatically at launch
  when unsubscribed, plus "Unlock Screen Divider…" in the menu.

## 6. After approval

- The old DMG/install.sh flow is legacy — App Store build handles login
  items via System Settings (SMAppService) and stores config inside the
  app sandbox container (`~/Library/Containers/com.vantagemethod.screendivider/`),
  so DMG users who switch start with a fresh default layout.
- Version bumps: raise `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` in
  `project.yml` AND `CFBundleShortVersionString`/`CFBundleVersion` in
  `Info.plist`, re-run `xcodegen generate`, archive, upload.

## Dev notes

- `swift build` dev runs have no App Store receipt, so the paywall would
  always block; export `SD_DEV_UNLOCK=1` (debug builds only) to bypass.
- `swift build` currently fails under bare Command Line Tools ("unable to
  lookup item 'PlatformPath'") — that's a CLT limitation, not a code error.
  Type-check with:
  `xcrun swiftc -typecheck -target arm64-apple-macos13.0 $(find Sources -name "*.swift")`
  Once Xcode is installed and selected, `swift build` works again.
