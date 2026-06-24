## 1.0.0

Initial release.

- FFmpeg-free native video trimming on **iOS, macOS, Android, Windows and Web**.
- Type-safe Dart ↔ native bindings via **Pigeon** (replaces the stringly-typed
  `MethodChannel` of `flutter_native_video_trimmer`).
- Same public API as `flutter_native_video_trimmer`: `loadVideo`, `trimVideo`,
  `clearCache` — drop-in compatible.
- New: `trimProgress` stream (0–100) via a Pigeon `EventChannel`.
- iOS/macOS: AVFoundation (`AVAssetExportSession`); true audio removal via
  `AVMutableComposition`.
- Android: Media3 Transformer with trim optimization.
- Windows: WinRT `Windows.Media.Editing.MediaComposition`.
- Web: WebCodecs + mp4box.js running inside a Web Worker; returns a `blob:` URL.
