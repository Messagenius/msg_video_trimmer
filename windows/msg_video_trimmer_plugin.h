#ifndef FLUTTER_PLUGIN_MSG_VIDEO_TRIMMER_PLUGIN_H_
#define FLUTTER_PLUGIN_MSG_VIDEO_TRIMMER_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/plugin_registrar_windows.h>
#include <winrt/Windows.System.h>

#include <memory>

#include "messages.g.h"
#include "video_manager.h"

namespace msg_video_trimmer {

// Flutter Windows plugin: implements the Pigeon host API on top of
// `VideoManager` and streams trim progress over an event channel.
class MsgVideoTrimmerPlugin : public flutter::Plugin,
                             public VideoTrimmerHostApi {
 public:
  static void RegisterWithRegistrar(
      flutter::PluginRegistrarWindows* registrar);

  MsgVideoTrimmerPlugin();
  ~MsgVideoTrimmerPlugin() override;

  MsgVideoTrimmerPlugin(const MsgVideoTrimmerPlugin&) = delete;
  MsgVideoTrimmerPlugin& operator=(const MsgVideoTrimmerPlugin&) = delete;

  // VideoTrimmerHostApi.
  void LoadVideo(
      const std::string& path,
      std::function<void(std::optional<FlutterError> reply)> result) override;
  void TrimVideo(
      const TrimRequest& request,
      std::function<void(ErrorOr<std::string> reply)> result) override;
  void ClearCache(
      std::function<void(std::optional<FlutterError> reply)> result) override;

 private:
  // Runs `fn` on the Flutter platform thread (the thread that owns the
  // channels). WinRT continuations resume on arbitrary threads.
  void RunOnPlatformThread(std::function<void()> fn);

  VideoManager video_manager_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      progress_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> progress_sink_;
  winrt::Windows::System::DispatcherQueue dispatcher_{nullptr};
};

}  // namespace msg_video_trimmer

#endif  // FLUTTER_PLUGIN_MSG_VIDEO_TRIMMER_PLUGIN_H_
