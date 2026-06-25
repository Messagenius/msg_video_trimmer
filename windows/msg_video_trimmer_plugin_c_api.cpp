#include "include/msg_video_trimmer/msg_video_trimmer_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "msg_video_trimmer_plugin.h"

void MsgVideoTrimmerPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  msg_video_trimmer::MsgVideoTrimmerPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
