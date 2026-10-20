# Overheard iOS

This is currently a **bare spike app**. It listens through the mic, runs BirdNET on the phone and lists the birds it hears, filtered to the species expected at your location this week. The design comes later; see `docs/design.md`. The detection pipeline lives in `OverheardKit/`.

## Build

1. **Model files:** these come from Git LFS: `git lfs install --local && git lfs pull`. The project bundles three files from `ml/models/coreml/`:
   - `BirdNETAudio.mlpackage`
   - `BirdNETMeta.mlpackage`
   - `species.json`
2. **Signing:** set your team once:
   ```sh
   cp apps/ios/Config/Local.xcconfig.example apps/ios/Config/Local.xcconfig
   # edit DEVELOPMENT_TEAM. Find your team ID in Xcode → Settings → Accounts:
   # select your Apple ID, then the team. A free "Personal Team" works.
   ```
   `Local.xcconfig` is gitignored, so each developer uses their own team.
3. **Xcode project:** generate it. It's gitignored, so regenerate it after changing `project.yml`:
   ```sh
   brew install xcodegen   # once
   cd apps/ios && xcodegen
   open Overheard.xcodeproj
   ```

## Run on your iPhone (free signing)

1. Plug in the phone. On the phone, turn on Settings → Privacy & Security → **Developer Mode** and restart.
2. Make sure your Apple ID is added in Xcode → Settings → Accounts. If Xcode says the bundle ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`.
3. Select your phone as the run destination and press **Run** (⌘R).
4. The first time, the phone asks you to trust the developer: Settings → General → VPN & Device Management → **Verify App**. If verifying fails, switch the phone to cellular and try again.
5. When you tap **Start walk**, the app asks for the microphone and then your location. "Approximate" location is enough.

Free-signed builds expire after 7 days. Run again from Xcode to reinstall.

## Demo walk (design work)

To see the screens filled in without going outside, turn on the `-demo` argument: **Product → Scheme → Edit Scheme → Run → Arguments**, tick `-demo`, and run. The app opens on a sample walk in the Ramble, with five birds, one rare bird, and one still being sketched. It's Debug-only and never saves anything.

To force a theme, add the argument `-themeChoice candlelight` (or `parchment`) next to it. `-startTab journal` (or `flock`, `me`) opens on another tab.

## Editor (VS Code / Cursor)

Run this once, then build in Xcode or with `xcodebuild`, so the Swift language server sees the iOS settings:

```sh
brew install xcode-build-server
xcode-build-server config -project apps/ios/Overheard.xcodeproj -scheme Overheard   # from the repo root
```

Without it, the editor checks app files as macOS code and flags iOS-only APIs like `AVAudioSession`.

## Field test checklist

- **Detections:** do common park birds show up (White-throated Sparrow, Blue Jay, Cardinal, Robin)?
- **False positives:** try lowering **Min confidence** to see what's borderline, and check how many wrong birds appear at 50%.
- **Location filter:** compare **Only birds expected here this week** on and off. The Stats section shows the location the filter is using.
- **Inference time:** check the Stats section. It should be well under 3,000 ms.
- **Screen locked:** does listening keep going when the phone is locked or in a pocket? Does the route keep recording?
- **Walks:** after End walk, does the walk show under Walks with the right birds, time, distance and map? Force-quit mid-walk: on relaunch the walk should be there, marked as cut short.
- **AirPods:** connect or disconnect them mid-session; listening should continue.
- **Battery:** how much drains per hour?
