import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'msg_video_trimmer',
    swiftOut: 'darwin/msg_video_trimmer/Sources/msg_video_trimmer/messages.g.swift',
    kotlinOut:
        'android/src/main/kotlin/com/messagenius/msg_video_trimmer/messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.messagenius.msg_video_trimmer',
    ),
    cppOptions: CppOptions(namespace: 'msg_video_trimmer'),
    cppHeaderOut: 'windows/messages.g.h',
    cppSourceOut: 'windows/messages.g.cpp',
  ),
)

/// Parameters for a single trim operation.
///
/// Times are in milliseconds and must satisfy `0 <= startTimeMs < endTimeMs`
/// and `endTimeMs <= duration` of the currently loaded video.
class TrimRequest {
  TrimRequest({
    required this.startTimeMs,
    required this.endTimeMs,
    required this.includeAudio,
  });

  int startTimeMs;
  int endTimeMs;
  bool includeAudio;
}

/// Host (native) API implemented on iOS, macOS, Android and Windows.
///
/// The web platform does not use this API; it implements the same Dart
/// platform interface directly using WebCodecs (see `src/web`).
@HostApi()
abstract class VideoTrimmerHostApi {
  /// Loads the video at [path] so it can be trimmed.
  @async
  void loadVideo(String path);

  /// Trims the currently loaded video and returns the output file path.
  @async
  String trimVideo(TrimRequest request);

  /// Deletes every `video_trimmer_*` output produced by this plugin.
  @async
  void clearCache();
}

/// Trim progress (0–100) streamed to Dart while [VideoTrimmerHostApi.trimVideo]
/// runs. Backed by a platform `EventChannel`.
@EventChannelApi()
abstract class VideoTrimmerEvents {
  double trimProgress();
}
