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
