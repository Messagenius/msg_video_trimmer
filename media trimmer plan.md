# Plan: `native_video_trimmer` — cross-platform native video trimming plugin

## Context

The existing `flutter_native_video_trimmer` package (v1.1.9) is a lightweight, FFmpeg-free
video trimmer that only supports **iOS** (AVFoundation) and **Android** (Media3 Transformer).
It uses a raw `MethodChannel` named `flutter_native_video_trimmer` with a handler-per-method
pattern, exposing three methods: `loadVideo(path)`, `trimVideo({startTimeMs, endTimeMs,
includeAudio})`, and `clearCache()`.

The goal is a **new standalone package** that keeps the same minimal trimming API but:
- Adds **macOS** and **Windows** support, plus **web** (via native WebCodecs).
- Does **all** trimming with native/platform APIs (no FFmpeg, no Dart-isolate processing) so
  heavy work never runs in the Flutter isolate.
- Uses **Pigeon** for type-safe Dart↔native bindings instead of stringly-typed channels.
- Uses the latest native APIs on each platform.

Outcome: one package, five platforms, type-safe, FFmpeg-free, with the same simple API the
original users already know.

---

## Summary of the original (reference for parity)

| Aspect | Original behavior to preserve |
|---|---|
| Public API | `loadVideo(String path)`, `trimVideo({required int startTimeMs, required int endTimeMs, bool includeAudio = true}) → String?`, `clearCache()` |
| Trim semantics | Times in **milliseconds**; output is an **mp4** written to a cache dir; returns the output **path**; validates `0 ≤ start < end ≤ duration` |
| Audio toggle | `includeAudio: false` removes/mutes audio |
| Cache | Output named `video_trimmer_<timestamp>.mp4` in platform cache dir; `clearCache()` deletes them |

New additions beyond parity: a **progress stream** (0–100) via a Pigeon `EventChannel`, and
the four new platforms.

---

## Target package layout

New repo / package name: **`native_video_trimmer`** (adjust if taken on pub.dev).

```
native_video_trimmer/
├── pubspec.yaml
├── pigeons/
│   └── messages.dart                      # Pigeon API + EventChannel definitions
├── lib/
│   ├── native_video_trimmer.dart          # barrel export
│   └── src/
│       ├── native_video_trimmer.dart      # public VideoTrimmer class
│       ├── video_trimmer_platform_interface.dart   # abstract (plugin_platform_interface)
│       ├── video_trimmer_pigeon.dart      # default impl -> calls generated HostApi
│       ├── messages.g.dart                # GENERATED (Pigeon, Dart)
│       └── web/
│           └── native_video_trimmer_web.dart   # WebCodecs impl (registers on web)
├── darwin/                                 # SHARED iOS + macOS (sharedDarwinSource)
│   ├── native_video_trimmer.podspec
│   └── Classes/
│       ├── NativeVideoTrimmerPlugin.swift  # implements generated HostApi
│       ├── VideoManager.swift              # AVFoundation trim logic
│       └── messages.g.swift                # GENERATED (Pigeon, Swift)
├── android/
│   ├── build.gradle
│   └── src/main/kotlin/.../
│       ├── NativeVideoTrimmerPlugin.kt
│       ├── VideoManager.kt                 # Media3 Transformer trim logic
│       └── messages.g.kt                   # GENERATED (Pigeon, Kotlin)
├── windows/
│   ├── CMakeLists.txt
│   ├── native_video_trimmer_plugin.cpp     # implements generated HostApi
│   ├── video_manager.cpp/.h                # WinRT MediaComposition trim logic
│   └── messages.g.cpp / messages.g.h       # GENERATED (Pigeon, C++)
└── example/                                # multi-platform example app
    └── lib/main.dart
```

`pubspec.yaml` plugin block:

```yaml
flutter:
  plugin:
    platforms:
      android:  { package: com.<org>.native_video_trimmer, pluginClass: NativeVideoTrimmerPlugin }
      ios:      { pluginClass: NativeVideoTrimmerPlugin, sharedDarwinSource: true }
      macos:    { pluginClass: NativeVideoTrimmerPlugin, sharedDarwinSource: true }
      windows:  { pluginClass: NativeVideoTrimmerPluginCApi }
      web:      { pluginClass: NativeVideoTrimmerWeb, fileName: src/web/native_video_trimmer_web.dart }
```

Deps: `plugin_platform_interface: ^2.1.8`, `web: ^1.1.0` (web JS interop); dev: `pigeon: ^22.x`.

---

## 1. Pigeon contract (`pigeons/messages.dart`)

Single source of truth; generates Dart, Swift, Kotlin, C++.

```dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  swiftOut: 'darwin/Classes/messages.g.swift',
  kotlinOut: 'android/src/main/kotlin/.../messages.g.kt',
  cppOptions: CppOptions(namespace: 'native_video_trimmer'),
  cppHeaderOut: 'windows/messages.g.h',
  cppSourceOut: 'windows/messages.g.cpp',
))

class TrimRequest {
  late int startTimeMs;
  late int endTimeMs;
  late bool includeAudio;
}

@HostApi()
abstract class VideoTrimmerHostApi {
  @async void loadVideo(String path);
  @async String trimVideo(TrimRequest request);   // returns output path / blob URL
  @async void clearCache();
}

// Progress 0–100 streamed during trim
@EventChannelApi()
abstract class VideoTrimmerEvents {
  double trimProgress();
}
```

Note: **Pigeon does not generate web code.** The web platform is implemented manually in Dart
against the same platform interface (Section 6). All four native platforms share the generated
`HostApi`.

---

## 2. Dart API layer (parity-preserving)

- `lib/src/video_trimmer_platform_interface.dart` — abstract `VideoTrimmerPlatform extends
  PlatformInterface` with `loadVideo`, `trimVideo`, `clearCache`, and a
  `Stream<double> trimProgress`. Mirrors the original's interface pattern.
- `lib/src/video_trimmer_pigeon.dart` — default instance for native platforms; delegates to the
  generated `VideoTrimmerHostApi` and exposes the `@EventChannelApi` stream.
- `lib/src/native_video_trimmer.dart` — public `VideoTrimmer` class, **same method signatures
  as the original** so migration is trivial, plus a `trimProgress` stream getter.
- `lib/native_video_trimmer.dart` — barrel export.

---

## 3. iOS + macOS — shared Darwin (AVFoundation)

Single `darwin/Classes` source compiled for both via `sharedDarwinSource: true`. Min versions:
**iOS 13 / macOS 10.15** (set in podspec). AVFoundation is identical on both.

- `NativeVideoTrimmerPlugin.swift`: registers, sets up `VideoTrimmerHostApi` + event channel,
  forwards to `VideoManager`.
- `VideoManager.swift`: port the original `VideoManager.swift` trim logic with modernizations:
  - Hold `currentAsset: AVAsset` from `loadVideo`.
  - Trim with `AVAssetExportSession(asset:presetName:AVAssetExportPresetHighestQuality)`,
    `outputFileType = .mp4`, `timeRange = CMTimeRange(start:end:)` (timescale 1000 for ms).
  - **Audio removal**: prefer building an `AVMutableComposition` containing only the video track
    when `includeAudio == false` (true removal), instead of the original's volume-0 audioMix.
  - Use Swift **async/await** (`export(to:as:)` on newer OS, else `exportAsynchronously`) and
    emit progress via the event channel by observing `exportSession.progress`.
  - Reuse original validation (`0 ≤ start < end ≤ duration`) and cache-dir naming
    (`video_trimmer_<timestamp>.mp4` in `.cachesDirectory`).
- `clearCache()`: delete `video_trimmer_*` files from the caches directory.
- `native_video_trimmer.podspec`: declares both `ios.deployment_target` and
  `osx.deployment_target`, no external deps (AVFoundation is system).

---

## 4. Android — Media3 Transformer (Kotlin)

Port the original Android implementation; bump to the **latest Media3** (e.g. `1.8.x`).

- `build.gradle`: `androidx.media3:media3-transformer` + `media3-common` (latest), Kotlin
  coroutines, `compileSdk 35`, `minSdk 21`.
- `VideoManager.kt`: keep the proven approach —
  `MediaItem.Builder().setClippingConfiguration(start/end ms)`, `EditedMediaItem.Builder()
  .setRemoveAudio(!includeAudio)`, `Transformer` with `experimentalSetTrimOptimizationEnabled(true)`,
  `suspendCancellableCoroutine` for async, output to `context.cacheDir`.
  - **Progress**: poll `transformer.getProgress(ProgressHolder)` on a ticker and push to the event
    channel.
- `NativeVideoTrimmerPlugin.kt`: implement the generated `VideoTrimmerHostApi`, run trims off the
  platform thread, marshal results back. `clearCache()` deletes `video_trimmer_*` in cacheDir.

---

## 5. Windows — WinRT `Windows.Media.Editing` (C++/WinRT)

Recommended native path (no FFmpeg): the **`Windows.Media.Editing.MediaComposition`** API.
Requires Windows 10 1809+. Implement with C++/WinRT in the Flutter Windows plugin.

- `video_manager.cpp`:
  - `loadVideo`: `StorageFile::GetFileFromPathAsync(path)` → `MediaClip::CreateFromFileAsync(file)`;
    cache the clip / source file.
  - `trimVideo`: set `clip.TrimTimeFromStart(startMs)` and `clip.TrimTimeFromEnd(duration-endMs)`
    (or build via `MediaComposition` + offsets), add to a `MediaComposition`, then
    `composition.RenderToFileAsync(outFile, MediaTrimmingPreference::Precise, encodingProfile)`
    using a default `MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD/Auto)`.
  - **Audio removal**: when `includeAudio == false`, render with a video-only encoding profile
    (drop the audio stream / set `profile.Audio(nullptr)`), or mute the clip.
  - **Progress**: `RenderToFileAsync` returns an `IAsyncOperationWithProgress`; forward its
    progress callback to the event channel.
  - Output to the app's temp/cache dir (`ApplicationData` or Flutter's temp path) as
    `video_trimmer_<timestamp>.mp4`.
- `native_video_trimmer_plugin.cpp`: implement the generated C++ `HostApi`, dispatch async WinRT
  ops, and return results via `flutter::MethodResult`-style completion that Pigeon wires up.
- `CMakeLists.txt`: link `windowsapp.lib` (WinRT), set C++17, register the plugin C-API symbol.

---

## 6. Web — native WebCodecs (manual Dart impl, no Pigeon)

`lib/src/web/native_video_trimmer_web.dart` registers `NativeVideoTrimmerWeb` as the platform
interface instance on web. Uses **browser-native** APIs via `package:web` + JS interop — no
FFmpeg.wasm, no Dart-side decoding loop beyond orchestration.

- **Demux/mux**: load **mp4box.js** (small JS lib) to demux the input MP4 into encoded samples and
  to mux the output. (WebCodecs decodes/encodes frames but does not handle MP4 containers.)
- **Trim pipeline** (runs in a **Web Worker** to keep the Flutter isolate/UI thread free):
  1. `loadVideo(url)` — fetch bytes (blob URL / asset URL), demux with mp4box.js, read track
     metadata and sample timestamps.
  2. `trimVideo` — select samples within `[startTimeMs, endTimeMs]`; feed video samples to a
     `VideoDecoder`, re-encode the in-range frames with `VideoEncoder` (rebasing timestamps to 0),
     and (if `includeAudio`) do the same with `AudioDecoder`/`AudioEncoder`; mux the result back
     to an MP4 with mp4box.js. Skip the audio encoder entirely when `includeAudio == false`.
  3. Emit progress (processed/total samples) to the event-stream equivalent.
  4. Return a **blob URL** string (web has no filesystem path) as the "path".
- `clearCache()`: revoke any object URLs created during the session.
- Note in README: web `trimVideo` returns a `blob:` URL, and codec support depends on the
  browser's WebCodecs implementation (Chromium-based fully; Safari/Firefox vary).

---

## 7. Example app

Update `example/lib/main.dart` to: pick/provide a video, call `loadVideo`, run `trimVideo` with a
start/end range and audio toggle, show the live progress stream, and play/preview the result.
Configure the example for all five platforms (`flutter create --platforms` already scaffolds
ios/android/macos/windows/web runners).

---

## Critical files to create/modify

- `pigeons/messages.dart` (contract — drives codegen for 4 platforms)
- `lib/src/native_video_trimmer.dart`, `lib/src/video_trimmer_platform_interface.dart`,
  `lib/src/video_trimmer_pigeon.dart`, `lib/src/web/native_video_trimmer_web.dart`
- `darwin/Classes/{NativeVideoTrimmerPlugin,VideoManager}.swift` + podspec
- `android/.../{NativeVideoTrimmerPlugin,VideoManager}.kt` + `build.gradle`
- `windows/{native_video_trimmer_plugin.cpp,video_manager.cpp/.h,CMakeLists.txt}`
- `pubspec.yaml` (plugin platforms + deps), `README.md`, `CHANGELOG.md`

Reuse as direct references (same algorithms, new package): the original iOS `VideoManager.swift`
trim/validation logic and the original Android `VideoManager.kt` Transformer logic.

---

## Verification

1. **Codegen**: `dart run pigeon --input pigeons/messages.dart` generates Dart/Swift/Kotlin/C++
   with no errors; `flutter analyze` is clean.
2. **iOS/macOS**: `cd example && flutter run -d <ios|macos>` — load a bundled sample mp4, trim a
   2s→5s range, confirm output plays, duration ≈ 3s, audio present; re-run with
   `includeAudio: false` and confirm silent output; confirm progress stream reaches 100.
3. **Android**: `flutter run -d <android>` — same checks; verify Media3 trim-optimization path and
   that the UI stays responsive (work is off the platform/isolate thread).
4. **Windows**: `flutter run -d windows` — same trim/audio/progress checks via WinRT render.
5. **Web**: `flutter run -d chrome` — load a sample mp4, trim, confirm the returned `blob:` URL
   plays the trimmed segment; verify the trim runs in a Web Worker (UI/isolate not blocked).
6. **Cache**: after several trims, call `clearCache()` and confirm `video_trimmer_*` outputs are
   removed (native) / object URLs revoked (web).
7. **Unit tests**: Dart tests mock the platform interface for `loadVideo`/`trimVideo`/`clearCache`;
   Pigeon-generated mocks verify argument marshalling.
