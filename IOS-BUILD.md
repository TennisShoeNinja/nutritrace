# Personal iOS build of NutriTrace (fork)

Brief for a Claude session on the Mac. Goal: a NutriTrace iPhone app for Alex's own phone, so he can use it for
a week and decide if it's worth keeping. Not for the App Store, and nothing goes upstream (no PRs or issues on
TraceApps/nutritrace unless Alex says so).

## Context
- Fork: `TennisShoeNinja/nutritrace` (of `TraceApps/nutritrace`), branch `ios`. Add `upstream` as a remote to pull releases.
- Server: NutriTrace v1.4.0 on cronpi, `https://cronpi.tail4ec703.ts.net/nutrition` (public via Tailscale Funnel,
  multi-user login; Alex types his own password). The app links to it like the Android app does.
- The Android app is this same Svelte/Vite web app in Capacitor 8 (`capacitor.config.ts`, `npm run build` -> `dist/`).
  Upstream's roadmap lists an iOS app as "pending hardware and Apple Developer account access"; nobody has done it.
- Plugins in `package.json` all have iOS support except `@devmaxime/capacitor-health-connect` (Android only).
- Alex already builds `TennisShoeNinja/routine-ios` (a widget app) on this Mac, so Xcode and signing are set up there.

## Steps
1. `npm ci`, `npm i @capacitor/ios@^8`, `npm run build`, `npx cap add ios`, `npx cap sync ios`.
2. Find every Health Connect / Android-only call (`grep -rn "HealthConnect\|isNativePlatform\|getPlatform" src`)
   and make sure iOS skips it cleanly (hide the Health Connect UI on iOS). Don't add Apple Health yet.
3. `ios/App/App/Info.plist`: `NSCameraUsageDescription` (barcode + food photos), `NSPhotoLibraryUsageDescription`,
   `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription` (Smart Log voice), `NSFaceIDUsageDescription` (biometric login).
4. Bundle id: change `appId` to something Alex owns, e.g. `com.tennisshoeninja.nutritrace` (`com.nutritrace.app` is upstream's).
   Signing: Alex's team in Xcode, same as routine-ios.
5. Run on Alex's iPhone. Link to the server above and sign in (Alex types the password).
6. Commit to `ios` with a short `IOS.md` on how to rebuild after pulling an upstream release.

## Done when
On the iPhone: signed in to the cronpi server; the diary shows the same goals and entries as the web app (2,200 kcal,
protein minimum 234 g); a barcode scan finds a product; a food photo uploads; nothing crashes on Android-only features.
Report anything that didn't work. Widgets are a later step (WidgetKit extension), not part of this.
