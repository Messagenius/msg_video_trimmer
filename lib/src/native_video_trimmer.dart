import 'dart:async';

import 'video_trimmer_platform_interface.dart';

/// FFmpeg-free, cross-platform native video trimmer.
///
/// Drop-in compatible with the original `flutter_native_video_trimmer` public
/// API, with an added [trimProgress] stream. Supported platforms: iOS, macOS,
/// Android, Windows and Web.
class VideoTrimmer {
  /// Loads a video file from the given [path] so it can be trimmed.
  ///
  /// On web, [path] is a URL (e.g. a `blob:` or asset URL).
  Future<void> loadVideo(String path) {
    return VideoTrimmerPlatform.instance.loadVideo(path);
  }

  /// Trims the loaded video from [startTimeMs] to [endTimeMs].
  ///
  /// Times are in milliseconds and must satisfy
  /// `0 <= startTimeMs < endTimeMs <= duration`. Set [includeAudio] to `false`
  /// to drop the audio track. Returns the path to the trimmed mp4 (a `blob:`
  /// URL on web), or `null` if trimming produced no output.
  Future<String?> trimVideo({
    required int startTimeMs,
    required int endTimeMs,
    bool includeAudio = true,
  }) {
    return VideoTrimmerPlatform.instance.trimVideo(
      startTimeMs: startTimeMs,
      endTimeMs: endTimeMs,
      includeAudio: includeAudio,
    );
  }

  /// Clears any cached files created during trimming.
  ///
  /// On web this revokes object URLs created during the session.
  Future<void> clearCache() {
    return VideoTrimmerPlatform.instance.clearCache();
  }

  /// Emits trim progress as a value in the range 0–100 while [trimVideo] runs.
  Stream<double> get trimProgress =>
      VideoTrimmerPlatform.instance.trimProgress;
}
