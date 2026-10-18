# Overheard iOS

This is currently the **BirdNET spike**: a bare app that listens through the mic, runs BirdNET on the phone and lists the birds it hears. The design comes later; see `docs/design.md`.

## Build

1. Build the model files: follow `ml/README.md`. The project bundles three files from `ml/models/coreml/`:
   - `BirdNETAudio.mlpackage`
   - `labels.txt`
   - `species-central-park.json`
2. Generate the Xcode project. It's gitignored, so regenerate it after changing `project.yml`:
   ```sh
   brew install xcodegen   # once
   cd apps/ios && xcodegen
   open Overheard.xcodeproj
   ```

## Run on your iPhone (free signing)

1. Plug in the phone. On the phone, turn on Settings → Privacy & Security → **Developer Mode** and restart.
2. In Xcode, open the Overheard target → **Signing & Capabilities**:
   - Turn on **Automatically manage signing**.
   - Set **Team** to your Apple ID ("Personal Team"). You may need to add your Apple ID first under Xcode → Settings → Accounts.
   - If Xcode says the bundle ID is taken, change it to something unique.
3. Select your phone as the run destination and press **Run** (⌘R).
4. The first time, the phone asks you to trust the developer: Settings → General → VPN & Device Management.

Free-signed builds expire after 7 days. Run again from Xcode to reinstall.

## Field test checklist

- **Detections:** do common park birds show up (White-throated Sparrow, Blue Jay, Cardinal, Robin)?
- **False positives:** try lowering **Min confidence** to see what's borderline, and check how many wrong birds appear at 50%.
- **Location filter:** compare results with the **Central Park species filter** on and off.
- **Inference time:** check the Stats section. It should be well under 3,000 ms.
- **Screen locked:** does listening keep going when the phone is locked or in a pocket?
- **Battery:** how much drains per hour?
