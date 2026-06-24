import 'messages.g.dart';
import 'video_trimmer_platform_interface.dart';

/// Default [VideoTrimmerPlatform] for the native platforms (iOS, macOS,
/// Android, Windows). Delegates to the Pigeon-generated [VideoTrimmerHostApi]
/// and exposes the `@EventChannelApi` progress stream.
class PigeonVideoTrimmer extends VideoTrimmerPlatform {
  PigeonVideoTrimmer({VideoTrimmerHostApi? hostApi})
      : _hostApi = hostApi ?? VideoTrimmerHostApi();

  final VideoTrimmerHostApi _hostApi;

  @override
  Future<void> loadVideo(String path) => _hostApi.loadVideo(path);

  @override
  Future<String?> trimVideo({
    required int startTimeMs,
    required int endTimeMs,
    bool includeAudio = true,
  }) {
    return _hostApi.trimVideo(
      TrimRequest(
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        includeAudio: includeAudio,
      ),
    );
  }

  @override
  Future<void> clearCache() => _hostApi.clearCache();

  @override
  Stream<double> get trimProgress => trimProgressStream();
}

/// Wraps the generated top-level `trimProgress()` event-channel function so it
/// can be referenced as a member (the generated name collides with the
/// platform-interface getter otherwise).
Stream<double> trimProgressStream() => trimProgress();
