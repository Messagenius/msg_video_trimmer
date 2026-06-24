import 'package:video_player/video_player.dart';

/// Web: there is no filesystem path; everything is a (blob/network) URL.
VideoPlayerController createPreviewController(String path,
    {required bool isBlob}) {
  return VideoPlayerController.networkUrl(Uri.parse(path));
}
