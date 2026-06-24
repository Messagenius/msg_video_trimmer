#include "video_manager.h"

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Editing.h>
#include <winrt/Windows.Media.MediaProperties.h>
#include <winrt/Windows.Media.Transcoding.h>
#include <winrt/Windows.Storage.h>

#include <chrono>
#include <filesystem>

namespace msg_video_trimmer {

using namespace winrt;
using namespace winrt::Windows::Foundation;
using namespace winrt::Windows::Media::Editing;
using namespace winrt::Windows::Media::MediaProperties;
using namespace winrt::Windows::Media::Transcoding;
using namespace winrt::Windows::Storage;

namespace {

std::wstring Widen(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                 static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      result.data(), size);
  return result;
}

std::string Narrow(std::wstring_view wide) {
  if (wide.empty()) return std::string();
  int size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                 static_cast<int>(wide.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

}  // namespace

void VideoManager::LoadVideo(
    const std::string& path,
    std::function<void(std::optional<std::string>)> done) {
  auto wide = Widen(path);
  [](VideoManager* self, std::wstring wpath,
     std::function<void(std::optional<std::string>)> cb) -> fire_and_forget {
    try {
      auto file = co_await StorageFile::GetFileFromPathAsync(wpath);
      auto clip = co_await MediaClip::CreateFromFileAsync(file);
      self->current_clip_ = clip;
      cb(std::nullopt);
    } catch (const winrt::hresult_error& e) {
      cb(Narrow(e.message()));
    } catch (...) {
      cb(std::string("Failed to load video"));
    }
  }(this, std::move(wide), std::move(done));
}

void VideoManager::TrimVideo(
    int64_t start_ms, int64_t end_ms, bool include_audio,
    std::function<void(double)> on_progress,
    std::function<void(std::optional<std::string>, std::optional<std::string>)>
        done) {
  if (current_clip_ == nullptr) {
    done(std::nullopt, std::string("No video loaded"));
    return;
  }
  if (start_ms < 0 || end_ms <= start_ms) {
    done(std::nullopt, std::string("Invalid time range"));
    return;
  }

  [](MediaClip source, int64_t start_ms, int64_t end_ms, bool include_audio,
     std::function<void(double)> on_progress,
     std::function<void(std::optional<std::string>, std::optional<std::string>)>
         cb) -> fire_and_forget {
    try {
      // Work on a clone so repeated trims of the same source are independent.
      auto clip = source.Clone();
      auto total = clip.OriginalDuration();
      auto start = std::chrono::milliseconds(start_ms);
      auto end = std::chrono::milliseconds(end_ms);
      clip.TrimTimeFromStart(TimeSpan(start));
      auto trim_from_end = total - TimeSpan(end);
      if (trim_from_end.count() > 0) {
        clip.TrimTimeFromEnd(trim_from_end);
      }

      MediaComposition composition;
      composition.Clips().Append(clip);

      // Build the output file in the temp directory.
      auto temp_dir = std::filesystem::temp_directory_path();
      auto folder =
          co_await StorageFolder::GetFolderFromPathAsync(temp_dir.wstring());
      auto timestamp = std::chrono::duration_cast<std::chrono::seconds>(
                           std::chrono::system_clock::now().time_since_epoch())
                           .count();
      auto name = L"video_trimmer_" + std::to_wstring(timestamp) + L".mp4";
      auto out_file = co_await folder.CreateFileAsync(
          name, CreationCollisionOption::ReplaceExisting);

      auto profile =
          MediaEncodingProfile::CreateMp4(VideoEncodingQuality::HD);
      if (!include_audio) {
        // Drop the audio stream entirely for a true audio removal.
        profile.Audio(nullptr);
      }

      auto render_op = composition.RenderToFileAsync(
          out_file, MediaTrimmingPreference::Precise, profile);
      render_op.Progress([on_progress](auto const&, double progress) {
        on_progress(progress);
      });
      auto result = co_await render_op;
      on_progress(100.0);
      if (result == TranscodeFailureReason::None) {
        cb(Narrow(out_file.Path()), std::nullopt);
      } else {
        cb(std::nullopt, std::string("Render failed"));
      }
    } catch (const winrt::hresult_error& e) {
      cb(std::nullopt, Narrow(e.message()));
    } catch (...) {
      cb(std::nullopt, std::string("Failed to trim video"));
    }
  }(current_clip_, start_ms, end_ms, include_audio, std::move(on_progress),
    std::move(done));
}

void VideoManager::ClearCache() {
  std::error_code ec;
  auto temp_dir = std::filesystem::temp_directory_path(ec);
  if (ec) return;
  for (auto& entry : std::filesystem::directory_iterator(temp_dir, ec)) {
    if (ec) break;
    const auto& p = entry.path();
    if (p.extension() == L".mp4" &&
        p.filename().wstring().rfind(L"video_trimmer_", 0) == 0) {
      std::filesystem::remove(p, ec);
    }
  }
}

}  // namespace msg_video_trimmer
