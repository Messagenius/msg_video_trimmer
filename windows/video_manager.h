#ifndef MSG_VIDEO_TRIMMER_VIDEO_MANAGER_H_
#define MSG_VIDEO_TRIMMER_VIDEO_MANAGER_H_

#include <winrt/Windows.Media.Editing.h>

#include <functional>
#include <optional>
#include <string>

namespace msg_video_trimmer {

// WinRT `Windows.Media.Editing` trim logic. All public methods are safe to call
// from the Flutter platform thread; async work runs on background threads and
// results are delivered through the supplied callbacks (which the caller is
// responsible for marshaling back to the platform thread if needed).
class VideoManager {
 public:
  // Loads the file and creates a MediaClip. Calls `done` with std::nullopt on
  // success or an error message on failure.
  void LoadVideo(const std::string& path,
                 std::function<void(std::optional<std::string> error)> done);

  // Trims the loaded clip to [start_ms, end_ms] and renders an mp4.
  // `on_progress` receives 0..100; `done` receives either the output path or an
  // error message.
  void TrimVideo(
      int64_t start_ms, int64_t end_ms, bool include_audio,
      std::function<void(double)> on_progress,
      std::function<void(std::optional<std::string> path,
                         std::optional<std::string> error)>
          done);

  // Deletes every `video_trimmer_*.mp4` in the temp directory.
  void ClearCache();

 private:
  winrt::Windows::Media::Editing::MediaClip current_clip_{nullptr};
};

}  // namespace msg_video_trimmer

#endif  // MSG_VIDEO_TRIMMER_VIDEO_MANAGER_H_
