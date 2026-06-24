#include "msg_video_trimmer_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.System.h>

#include <memory>

namespace msg_video_trimmer {

namespace {
constexpr char kProgressChannel[] =
    "dev.flutter.pigeon.msg_video_trimmer.VideoTrimmerEvents.trimProgress";
}  // namespace

void MsgVideoTrimmerPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<MsgVideoTrimmerPlugin>();

  VideoTrimmerHostApi::SetUp(registrar->messenger(), plugin.get());

  plugin->progress_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), kProgressChannel,
          &flutter::StandardMethodCodec::GetInstance());

  auto* plugin_ptr = plugin.get();
  auto handler = std::make_unique<
      flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
      [plugin_ptr](const flutter::EncodableValue*,
                   std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                       events)
          -> std::unique_ptr<flutter::StreamHandlerError<
              flutter::EncodableValue>> {
        plugin_ptr->progress_sink_ = std::move(events);
        return nullptr;
      },
      [plugin_ptr](const flutter::EncodableValue*)
          -> std::unique_ptr<flutter::StreamHandlerError<
              flutter::EncodableValue>> {
        plugin_ptr->progress_sink_.reset();
        return nullptr;
      });
  plugin->progress_channel_->SetStreamHandler(std::move(handler));

  registrar->AddPlugin(std::move(plugin));
}

MsgVideoTrimmerPlugin::MsgVideoTrimmerPlugin() {
  // Captured on the platform thread so callbacks can be marshaled back to it.
  dispatcher_ =
      winrt::Windows::System::DispatcherQueue::GetForCurrentThread();
}

MsgVideoTrimmerPlugin::~MsgVideoTrimmerPlugin() = default;

void MsgVideoTrimmerPlugin::RunOnPlatformThread(std::function<void()> fn) {
  if (dispatcher_) {
    dispatcher_.TryEnqueue([fn = std::move(fn)]() { fn(); });
  } else {
    // Fallback: no dispatcher available, run inline.
    fn();
  }
}

void MsgVideoTrimmerPlugin::LoadVideo(
    const std::string& path,
    std::function<void(std::optional<FlutterError> reply)> result) {
  video_manager_.LoadVideo(
      path, [this, result](std::optional<std::string> error) {
        RunOnPlatformThread([result, error]() {
          if (error) {
            result(FlutterError("load_failed", *error));
          } else {
            result(std::nullopt);
          }
        });
      });
}

void MsgVideoTrimmerPlugin::TrimVideo(
    const TrimRequest& request,
    std::function<void(ErrorOr<std::string> reply)> result) {
  video_manager_.TrimVideo(
      request.start_time_ms(), request.end_time_ms(), request.include_audio(),
      [this](double progress) {
        RunOnPlatformThread([this, progress]() {
          if (progress_sink_) {
            progress_sink_->Success(flutter::EncodableValue(progress));
          }
        });
      },
      [this, result](std::optional<std::string> path,
                     std::optional<std::string> error) {
        RunOnPlatformThread([result, path, error]() {
          if (path) {
            result(ErrorOr<std::string>(*path));
          } else {
            result(ErrorOr<std::string>(
                FlutterError("trim_failed", error.value_or("Trim failed"))));
          }
        });
      });
}

void MsgVideoTrimmerPlugin::ClearCache(
    std::function<void(std::optional<FlutterError> reply)> result) {
  video_manager_.ClearCache();
  result(std::nullopt);
}

}  // namespace msg_video_trimmer
