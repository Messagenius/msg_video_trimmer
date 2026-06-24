#
# Shared podspec for iOS and macOS (sharedDarwinSource). Kept alongside
# Package.swift so the plugin builds with both CocoaPods and Swift Package
# Manager. Run `pod lib lint msg_video_trimmer.podspec` to validate.
#
Pod::Spec.new do |s|
  s.name             = 'msg_video_trimmer'
  s.version          = '1.0.0'
  s.summary          = 'FFmpeg-free native video trimming for Flutter.'
  s.description      = <<-DESC
Cross-platform, type-safe video trimming using AVFoundation on iOS and macOS.
No FFmpeg dependency.
                       DESC
  s.homepage         = 'https://github.com/messagenius/msg_video_trimmer'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Messagenius' => 'https://github.com/messagenius' }
  s.source           = { :path => '.' }
  s.source_files     = 'msg_video_trimmer/Sources/msg_video_trimmer/**/*'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'msg_video_trimmer_privacy' => ['msg_video_trimmer/Sources/msg_video_trimmer/PrivacyInfo.xcprivacy']
  }
end
