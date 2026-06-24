import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'video_trimmer_pigeon.dart';

/// The interface that every platform implementation of `msg_video_trimmer`
/// must implement.
///
/// Mirrors the original `flutter_native_video_trimmer` interface so migration
/// is a one-line dependency swap, and adds a [trimProgress] stream.
abstract class VideoTrimmerPlatform extends PlatformInterface {
  /// Constructs a [VideoTrimmerPlatform].
  VideoTrimmerPlatform() : super(token: _token);

  static final Object _token = Object();

  static VideoTrimmerPlatform _instance = PigeonVideoTrimmer();

  /// The default instance of [VideoTrimmerPlatform] to use.
  ///
  /// Defaults to [PigeonVideoTrimmer] (iOS, macOS, Android, Windows). The web
  /// implementation registers itself via the plugin registrant.
  static VideoTrimmerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [VideoTrimmerPlatform] when they
  /// register themselves.
  static set instance(VideoTrimmerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Loads the video at [path] so it can be trimmed.
  Future<void> loadVideo(String path) {
    throw UnimplementedError('loadVideo() has not been implemented.');
  }

  /// Trims the loaded video from [startTimeMs] to [endTimeMs] (milliseconds).
  ///
  /// Set [includeAudio] to `false` to drop the audio track. Returns the path
  /// to the trimmed output (a `blob:` URL on web).
  Future<String?> trimVideo({
    required int startTimeMs,
    required int endTimeMs,
    bool includeAudio = true,
  }) {
    throw UnimplementedError('trimVideo() has not been implemented.');
  }

  /// Clears any cached files created during trimming.
  Future<void> clearCache() {
    throw UnimplementedError('clearCache() has not been implemented.');
  }

  /// Emits trim progress as a value in the range 0–100 while [trimVideo] runs.
  Stream<double> get trimProgress {
    throw UnimplementedError('trimProgress has not been implemented.');
  }
}
