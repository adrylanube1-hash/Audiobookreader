# audiobookreader for iOS

The iOS client targets iOS 15 or newer and uses the same generated model catalogue as Android, except PocketTTS, which is intentionally excluded. Local synthesis uses sherpa-onnx; Edge voices are fetched at runtime and clearly identified as online voices.

## Generate and build on macOS

```bash
./gradlew :shared:exportIosModelCatalog
bash scripts/prepare-ios-resources.sh
brew install xcodegen
cd iosApp
xcodegen generate
xcodebuild -project audiobookreader.xcodeproj -scheme audiobookreader \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The unsigned Simulator build does not require an Apple account. Building for an iPhone or publishing to TestFlight/App Store requires an Apple Developer team and Apple signing credentials; those credentials must be stored outside this repository.
