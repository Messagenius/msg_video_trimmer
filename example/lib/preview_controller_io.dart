import 'dart:io';

import 'package:video_player/video_player.dart';

/// Native: build a controller from a local file path.
VideoPlayerController createPreviewController(String path, {required bool isBlob}) {
  if (isBlob) {
    return VideoPlayerController.networkUrl(Uri.parse(path));
  }
  return VideoPlayerController.file(File(path));
}
