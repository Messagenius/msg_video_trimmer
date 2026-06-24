import AVFoundation
import Foundation

/// AVFoundation-based trim logic shared by iOS and macOS.
///
/// Ported from the original `flutter_native_video_trimmer` `VideoManager`,
/// modernized with: true audio removal via `AVMutableComposition`, async/await,
/// and progress reporting through a callback (wired to the Pigeon event channel).
final class VideoManager {
  private var currentAsset: AVAsset?
  private let fileManager = FileManager.default
  private var progressTimer: Timer?

  func loadVideo(path: String) throws {
    guard fileManager.fileExists(atPath: path) else {
      throw VideoError.fileNotFound
    }
    currentAsset = AVAsset(url: URL(fileURLWithPath: path))
  }

  /// Trims the loaded asset. `onProgress` is invoked with values in 0...100.
  func trimVideo(
    startTimeMs: Int64,
    endTimeMs: Int64,
    includeAudio: Bool,
    onProgress: @escaping (Double) -> Void,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    guard let asset = currentAsset else {
      completion(.failure(VideoError.noVideoLoaded))
      return
    }

    // Validate the requested range against the asset duration.
    let durationMs = Int64(CMTimeGetSeconds(asset.duration) * 1000)
    guard startTimeMs >= 0, endTimeMs > startTimeMs, endTimeMs <= durationMs else {
      completion(.failure(VideoError.invalidTimeRange))
      return
    }

    let startTime = CMTime(value: startTimeMs, timescale: 1000)
    let endTime = CMTime(value: endTimeMs, timescale: 1000)
    let timeRange = CMTimeRange(start: startTime, end: endTime)

    // Build the export source. When audio must be dropped we compose a
    // video-only asset for a true removal (vs. muting via audioMix).
    let exportAsset: AVAsset
    if includeAudio {
      exportAsset = asset
    } else {
      let composition = AVMutableComposition()
      guard
        let videoTrack = asset.tracks(withMediaType: .video).first,
        let compositionTrack = composition.addMutableTrack(
          withMediaType: .video,
          preferredTrackID: kCMPersistentTrackID_Invalid)
      else {
        completion(.failure(VideoError.unsupportedFormat))
        return
      }
      do {
        try compositionTrack.insertTimeRange(
          CMTimeRange(start: .zero, duration: asset.duration),
          of: videoTrack,
          at: .zero)
        compositionTrack.preferredTransform = videoTrack.preferredTransform
      } catch {
        completion(.failure(error))
        return
      }
      exportAsset = composition
    }

    let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: exportAsset)
    guard compatiblePresets.contains(AVAssetExportPresetHighestQuality),
      let exportSession = AVAssetExportSession(
        asset: exportAsset, presetName: AVAssetExportPresetHighestQuality)
    else {
      completion(.failure(VideoError.exportSessionFailed))
      return
    }

    let timestamp = Int64(Date().timeIntervalSince1970)
    let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let outputURL = cacheDir.appendingPathComponent("video_trimmer_\(timestamp).mp4")
    try? fileManager.removeItem(at: outputURL)

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .mp4
    exportSession.timeRange = timeRange

    // Poll export progress on the main run loop and forward it.
    onProgress(0)
    let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
      onProgress(Double(exportSession.progress) * 100.0)
    }
    RunLoop.main.add(timer, forMode: .common)
    progressTimer = timer

    exportSession.exportAsynchronously { [weak self] in
      self?.progressTimer?.invalidate()
      self?.progressTimer = nil
      switch exportSession.status {
      case .completed:
        onProgress(100)
        completion(.success(outputURL.path))
      case .failed:
        completion(.failure(exportSession.error ?? VideoError.exportFailed))
      case .cancelled:
        completion(.failure(VideoError.exportCancelled))
      default:
        completion(.failure(VideoError.unknown))
      }
    }
  }

  func clearCache() {
    let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
    guard let enumerator = fileManager.enumerator(at: cacheDir, includingPropertiesForKeys: nil)
    else { return }
    while let url = enumerator.nextObject() as? URL {
      if url.pathExtension == "mp4", url.lastPathComponent.hasPrefix("video_trimmer_") {
        try? fileManager.removeItem(at: url)
      }
    }
  }
}

enum VideoError: LocalizedError {
  case fileNotFound
  case noVideoLoaded
  case unsupportedFormat
  case exportSessionFailed
  case exportFailed
  case exportCancelled
  case invalidTimeRange
  case unknown

  var errorDescription: String? {
    switch self {
    case .fileNotFound: return "Video file not found"
    case .noVideoLoaded: return "No video is currently loaded"
    case .unsupportedFormat: return "Video format is not supported"
    case .exportSessionFailed: return "Failed to create export session"
    case .exportFailed: return "Failed to export video"
    case .exportCancelled: return "Video export was cancelled"
    case .invalidTimeRange:
      return
        "Invalid time range. Start must be >= 0, end must be > start and within the video duration"
    case .unknown: return "An unknown error occurred"
    }
  }
}
