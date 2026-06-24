import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Forwards the Pigeon `VideoTrimmerHostApi` to [VideoManager] and streams
/// trim progress over the generated event channel. Shared by iOS and macOS via
/// `sharedDarwinSource`.
public class MsgVideoTrimmerPlugin: NSObject, FlutterPlugin, VideoTrimmerHostApi {
  private let videoManager = VideoManager()
  private let progressHandler = TrimProgressHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = MsgVideoTrimmerPlugin()
    #if os(iOS)
      let messenger = registrar.messenger()
    #elseif os(macOS)
      let messenger = registrar.messenger
    #endif
    VideoTrimmerHostApiSetup.setUp(binaryMessenger: messenger, api: instance)
    TrimProgressStreamHandler.register(
      with: messenger, streamHandler: instance.progressHandler)
  }

  func loadVideo(path: String, completion: @escaping (Result<Void, Error>) -> Void) {
    do {
      try videoManager.loadVideo(path: path)
      completion(.success(()))
    } catch {
      completion(.failure(error))
    }
  }

  func trimVideo(
    request: TrimRequest, completion: @escaping (Result<String, Error>) -> Void
  ) {
    videoManager.trimVideo(
      startTimeMs: request.startTimeMs,
      endTimeMs: request.endTimeMs,
      includeAudio: request.includeAudio,
      onProgress: { [weak self] progress in
        DispatchQueue.main.async {
          self?.progressHandler.send(progress)
        }
      },
      completion: { result in
        DispatchQueue.main.async { completion(result) }
      })
  }

  func clearCache(completion: @escaping (Result<Void, Error>) -> Void) {
    videoManager.clearCache()
    completion(.success(()))
  }
}

/// Captures the event-channel sink so progress can be pushed during a trim.
class TrimProgressHandler: TrimProgressStreamHandler {
  private var sink: PigeonEventSink<Double>?

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<Double>) {
    self.sink = sink
  }

  override func onCancel(withArguments arguments: Any?) {
    sink = nil
  }

  func send(_ value: Double) {
    sink?.success(value)
  }
}
