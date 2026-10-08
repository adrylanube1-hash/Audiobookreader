# audiobookreader

Android, iOS and desktop PDF/EPUB/text reader with local text-to-speech and background playback.

## Current features

- Import documents through Android's document picker.
- Extract text from PDF, EPUB, text, and HTML files.
- Downloadable multilingual Sherpa-ONNX model catalog with language filtering.
- Models are downloaded and used inside the app; they are not registered as system TTS engines.
- After a download completes, the model is selected automatically and its actual contents are validated, including packages containing nested directories.
- `OfflineTts` adapter for Piper/VITS, Coqui VITS, Mimic3 VITS, Kokoro, Supertonic and ZipVoice, plus the native multilingual PocketTTS.cpp runtime.
- Edge TTS voices loaded from the live public voice catalogue and marked `ONLINE`; no Edge model files are bundled or downloaded.
- Edge TTS requires an explicit first-use disclosure before any book fragment is sent to Microsoft, and consent can be revoked in Settings.
- Sequential model-download queue with per-model progress and removable pending entries.
- License-aware downloads: models with additional conditions show their license, attribution, obligations, and accept/reject action before downloading.
- Chunk-based PCM-to-WAV generation with a Media3 playlist.
- Resumable progressive generation: playback starts after the first chunks are ready, and temporary look-ahead audio is removed when an unfinished book is stopped.
- `MediaSessionService` for notifications, system controls, lock-screen playback, and playback outside the app.
- Persistent media controls in the notification shade and on the lock screen, including pause/resume, 15-second rewind, 30-second forward, and stop.
- Reading percentage, exact chunk position, bookmarks, position reset, and local progress persistence.
- Visual highlighting of the complete chunk currently being played. Manual scrolling is preserved; any chunk can be tapped to select it as the starting point, even when earlier audio has not been prepared.
- Previous/next chunk navigation and a seek bar for prepared audio.
- Per-book settings: downloaded model, reading speed, named Kokoro/Supertonic voice, and voice-cloning reference. Changing the speed or voice clears that model's generated audio so it can be regenerated without mixing settings.
- Prepared-audio percentage and size per book, per-book or global cache cleanup, and a 512 MB limit to prevent excessive storage use.
- System, light, and dark appearance modes, with reading-specific contrast.
- Local ONNX model import from Settings. The user provides an ISO 639-1/639-2/639-3 language code (`es` or `spa`, for example), and `tokens.txt` is required; `.onnx.json`, lexicons, and other auxiliary files can also be selected. Files are stored inside audiobookreader's private sandbox.
- Original app icon in `assets/bookreader-icon.png`, also used by the APK.
- Third-party credits and license references are available in `THIRD_PARTY_NOTICES.md` and in the installed app assets.

The project is intended for Android Studio. Signed release outputs are generated at `app/build/outputs/apk/release/` and `app/build/outputs/bundle/release/` when the ignored local signing configuration is present. The APK contains the native engine, but no TTS models or generated audio; both are managed at runtime.

The [privacy policy](PRIVACY_POLICY.md) explains local processing and optional Edge TTS transmission. Maintainers should complete [the Google Play release checklist](docs/GOOGLE_PLAY_RELEASE_CHECKLIST.md) for every store submission.

## iOS target

`iosApp` is a native SwiftUI client for iOS 15 and newer. It provides the bookshelf, PDF/EPUB/text import, paragraph-aware reader, chunk selection/highlighting, automatic progress, bookmarks, per-book speed and voice settings, downloadable local models, Edge online voices, model licenses, download queue, generated-audio cleanup, background playback and lock-screen controls. It uses sherpa-onnx's official iOS XCFramework for Piper/VITS, Coqui, Mimic3, Kokoro, Supertonic and ZipVoice. PocketTTS is intentionally excluded from iOS.

The iOS model catalogue is generated from the Android/shared catalogue with `./gradlew :shared:exportIosModelCatalog`, so the platforms do not maintain separate hard-coded lists. See [iosApp/README.md](iosApp/README.md) for the macOS build command. `.github/workflows/mobile-prerelease.yml` builds an unsigned Android debug APK and unsigned iOS Simulator app on every push to `main`, then publishes both in the `mobile-debug` prerelease. No Android or Apple signing material is read or uploaded by that workflow.

## Desktop targets

The desktop module uses the shared Kotlin core and Compose Desktop. It opens PDF, EPUB, HTML, and text documents, preserves paragraph-aware segmentation, provides a bookshelf library with persistent per-book position/bookmarks/cache controls, generates and plays selected fragments with the desktop sherpa-onnx JVM engine, exposes Models and Settings, downloads local model packages beside the executable, imports local ONNX/Piper files with ISO 639-2 language codes, and loads the full Edge voice catalogue online. Kokoro is one shared downloadable package with its voices selected per book; Supertonic is one package per language with its ten voices selected per book. Linux packaging uses `:desktop:packageDeb` plus `scripts/package-appimage.sh`; Windows packaging uses `:desktop:packageMsi` and `:desktop:packageExe` on a Windows build machine. Native Gradle packaging tasks run on their target operating system; an alternative Windows packaging path using Wine is documented below.

### Windows installers

On Windows x64, install JDK 21 and WiX 3, then run:

```powershell
.\gradlew.bat :desktop:packageMsi :desktop:packageExe
```

The installers include Java, the Windows graphics/TTS libraries and the audiobookreader icon. They support per-user installation, a selectable destination and Start Menu/desktop shortcuts. Outputs are in `desktop/build/compose/binaries/main/msi/` and `desktop/build/compose/binaries/main/exe/`.

Linux can also package the same JVM code with a Windows JDK under Wine:

```bash
./gradlew :desktop:stageWindows
export BOOKREADER_WINDOWS_JDK=/absolute/path/to/windows-jdk-21
export BOOKREADER_WIX_DIR=/absolute/path/to/wix-3.11.2
export WINEPREFIX=/absolute/path/to/dedicated-wine-prefix
xvfb-run -a bash scripts/package-windows-wine.sh
```

This path requires Wine 10 with Wine Mono 9.4 installed in that prefix, the Windows x64 JDK, WiX **3.11.2.4516**, and `x86_64-w64-mingw32-gcc`. The small WiX launcher adapter restores the version banner omitted by Wine Mono and skips ICE validation, which Wine cannot execute; native Windows builds keep ICE validation. The adapter is a build tool and is not shipped in the application. Windows installers are not Authenticode-signed; Android signing keys are not used for Windows.

### Desktop playback fixes (0.1.8)

Local playback starts when the selected fragment is ready and continues through the book, keeping one fragment ahead and reusing one TTS engine per session. WAV output is buffered. Stop cancels pending work; because native inference cannot safely be interrupted, cleanup waits for the in-flight inference to return before discarding its result. Clear generated audio stops playback and removes that book's cached audio (including older cache layouts) without removing models or other books.

Cache entries include the text, voice, speaker and speed. Reading position is saved at fragment transitions, every 20 seconds during playback and on Stop; bookmarks and per-book voice/speed settings survive restarts. Desktop regression tests use fake inference/audio outputs and do not play sound: `./gradlew :desktop:test :shared:test`.

## Release signing

Release signing is read from `keystore.properties`, which is excluded from Git. SHA-256 fingerprints shown by Google are not private keys and cannot sign builds; use the upload keystore registered in Google Play Console. See `keystore.properties.example` and run `./gradlew assembleRelease`. No fingerprints, public keys, or secrets are stored in the repository.

## Supported model families

The list was cross-checked against `scripts/apk/generate-tts-apk-script.py` from the Sherpa-ONNX checkout:

- Piper/VITS: Sherpa-ONNX's catalog for dozens of languages, including Miro, Davefx, and Sharvard for `es_ES`.
- Coqui VITS and Mimic3 VITS: Sherpa-ONNX packages that the `OfflineTts` engine can run internally.
- Kokoro: the v1.0 multilingual package with 54 verified voice embeddings, including the three Spanish voices, and its INT8 variant. The Android adapter passes the selected Kokoro language to Sherpa-ONNX instead of relying on the default language.
- Supertonic 3 INT8: one shared package, 31 languages and ten built-in speakers (`M1`–`M5`, `F1`–`F5`).
- PocketTTS INT8: local multilingual zero-shot voice cloning from a reference WAV. English, French, German, Italian, Portuguese and Spanish language packs are downloaded independently; all voices in a pack reuse the same model.
- ZipVoice Distill INT8: local Chinese/English zero-shot cloning from a WAV and its exact transcript; the Vocos vocoder is installed automatically.

audiobookreader uses a verified 54-voice Kokoro v1.0 bundle, including the Spanish `ef_dora`, `em_alex` and `em_santa` embeddings. Model weights are never bundled in the Android APK; they are downloaded on demand and validated after extraction.

## Technical references

- [Sherpa-ONNX Android TTS](https://github.com/k2-fsa/sherpa-onnx/tree/master/android/SherpaOnnxTtsEngine)
- [OfflineTts Kotlin API](https://github.com/k2-fsa/sherpa-onnx/blob/master/sherpa-onnx/kotlin-api/Tts.kt)
- [APK generator catalog](https://github.com/k2-fsa/sherpa-onnx/blob/master/scripts/apk/generate-tts-apk-script.py)
- [Sherpa-ONNX pretrained TTS models](https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/index.html)
- [Kokoro-82M Spanish voices](https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md)
