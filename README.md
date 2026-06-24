# msg_video_trimmer

Cross-platform, **FFmpeg-free** native video trimming for Flutter. One package,
five platforms, type-safe bindings via [Pigeon](https://pub.dev/packages/pigeon).

| Platform | Engine | Min version |
|---|---|---|
| iOS | AVFoundation (`AVAssetExportSession`) | iOS 13 |
| macOS | AVFoundation (`AVAssetExportSession`) | macOS 10.15 |
| Android | Media3 Transformer | minSdk 21 |
| Windows | WinRT `Windows.Media.Editing` | Windows 10 1809 |
| Web | WebCodecs + mp4box.js (Web Worker) | Chromium-based browsers |

All trimming is done with native/platform APIs — no FFmpeg, and the heavy work
never runs on the Flutter isolate.

## Migrating from `flutter_native_video_trimmer`

The public API is unchanged, so migration is a dependency swap plus a renamed
import:

```dart
// import 'package:flutter_native_video_trimmer/flutter_native_video_trimmer.dart';
import 'package:msg_video_trimmer/msg_video_trimmer.dart';
```

## Usage

```dart
import 'package:msg_video_trimmer/msg_video_trimmer.dart';

final trimmer = VideoTrimmer();

// Optional: observe progress (0–100) while trimming.
final sub = trimmer.trimProgress.listen((p) => print('progress: $p%'));

await trimmer.loadVideo('/path/to/video.mp4'); // a URL on web

final outputPath = await trimmer.trimVideo(
  startTimeMs: 2000,
  endTimeMs: 5000,
  includeAudio: true, // set false to drop the audio track
);
print('Trimmed video at: $outputPath'); // a blob: URL on web

await trimmer.clearCache(); // deletes video_trimmer_* outputs (revokes blob URLs on web)
await sub.cancel();
```

### Semantics

- Times are in **milliseconds** and must satisfy
  `0 <= startTimeMs < endTimeMs <= duration`.
- Output is an **mp4** named `video_trimmer_<timestamp>.mp4` in the platform
  cache directory. `trimVideo` returns its path.
- On **web** there is no filesystem: `trimVideo` returns a `blob:` URL, and
  codec support depends on the browser's WebCodecs implementation (Chromium is
  fully supported; Safari/Firefox vary).

## How it works

A single [Pigeon contract](pigeons/messages.dart) generates the Dart, Swift,
Kotlin and C++ bindings for the four native platforms. The web platform
implements the same Dart platform interface manually using browser-native
WebCodecs, with the demux/decode/encode/mux pipeline running in a Web Worker so
the UI thread stays responsive.

To regenerate the bindings after editing the contract:

```sh
dart run pigeon --input pigeons/messages.dart
```

## License

MIT
