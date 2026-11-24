# Personal iOS build

The `ios` branch of this fork adds a Capacitor iOS shell around the same web app the Android build uses.
It's for personal use only and nothing here goes upstream.

## What differs from upstream
- `capacitor.config.ts`: `appId` is `com.tennisshoeninja.nutritrace`.
- `ios/`: Capacitor iOS project using **CocoaPods**, not SPM. Two plugins have no `Package.swift`:
  `@capacitor-mlkit/barcode-scanning` and `@capacitor-community/speech-recognition`.
  The deployment target is iOS 16.0 because MLKit 8 needs at least 15.5.
- Signing: automatic, team `5MAJ9SJU43` (same as routine-ios).
- `Info.plist` has usage strings for camera, photo library, microphone, speech recognition and Face ID.
- `src/lib/platform.js` exports `isAndroid` / `isIOS`. Health Connect (`health-connect.js`, sync, the
  Settings → Wellness card, the Wellness/Statistics/Trace reads) and the Fold plugin check `isAndroid`,
  not `isNative`. `healthConnectEnabled` syncs through the server, so it can be `true` on the iPhone too.
  Leave the setting alone and check the platform where it's used.

## Keeping the app in step with the web app
The iPhone app ships its own copy of the web app (`dist/`, copied into the app at build time). It does
**not** pick up frontend changes from the server. After you change the web app on `ios`:
- **Frontend only** (`src/`): pull on the Mac, then build, sync and install (the commands below, from
  `npm run build` on). cronpi doesn't need anything.
- **Server changed too** (`server/`): also rebuild `nutritrace:ios` on cronpi (see Server below).

## Rebuild after an upstream release
```bash
git fetch upstream --tags
git checkout ios
git merge upstream/main          # or the release tag, e.g. v1.5.0
```
Resolve conflicts. Then check that any new Health Connect / Android-only code checks `isAndroid`:
```bash
grep -rn "HealthConnect\|health-connect\|registerPlugin\|isNativePlatform\|getPlatform" src
```
Build and sync. CocoaPods needs a UTF-8 locale, or `pod install` fails with an `Encoding::CompatibilityError`:
```bash
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
npm ci
npm run build
npx cap sync ios
```
Then run it on the phone from Xcode (`npx cap open ios`, pick the iPhone, Run), or from the command line:
```bash
cd ios/App
xcodebuild -workspace App.xcworkspace -scheme App -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl list devices
xcrun devicectl device install app --device <identifier> build/Build/Products/Debug-iphoneos/App.app
```
The phone must be unlocked during the install, or the developer disk image won't mount.

If a new plugin is added upstream, check whether it supports iOS. `npx cap sync ios` adds it to the Podfile.

## Server
In the app, choose the server option and enter `https://cronpi.tail4ec703.ts.net/nutrition`, then sign in.

**The stock server image doesn't work with the iOS app.** On iOS the app's pages load from
`capacitor://app.nutritrace.local` (WKWebView won't let Capacitor use `https://` for this), and
upstream's CORS allowlist in `server/index.js` only has the Android origin `https://app.nutritrace.local`.
Sign-in still works because it goes through native HTTP, but every later request is blocked, and the app
shows "Can't reach <server>". This branch adds the iOS origin to the allowlist. cronpi has to run an image
built from this branch until upstream accepts that origin.

On cronpi, in a checkout of this fork:
```bash
git fetch origin && git checkout ios && git pull
docker build -t nutritrace:ios .
```
In cronpi's compose file, change `image: ghcr.io/traceapps/nutritrace:...` to `image: nutritrace:ios`, keep the
volumes and env as they are, then:
```bash
docker compose up -d
```
Check it:
```bash
curl -si -X OPTIONS -H "Origin: capacitor://app.nutritrace.local" -H "Access-Control-Request-Method: GET" https://cronpi.tail4ec703.ts.net/nutrition/api/health | grep -i allow-origin
```
It should print `access-control-allow-origin: capacitor://app.nutritrace.local`. After each upstream release, merge it
into `ios` (see above) and rebuild this image instead of pulling upstream's.
