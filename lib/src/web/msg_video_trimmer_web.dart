import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import '../video_trimmer_platform_interface.dart';
import 'trimmer_worker.dart';

/// Web implementation of [VideoTrimmerPlatform] backed by WebCodecs + mp4box.js.
///
/// All heavy lifting runs inside a module [web.Worker] (see [trimmerWorkerSource]),
/// so the Flutter UI/isolate is never blocked. `trimVideo` returns a `blob:` URL
/// because the browser has no filesystem path.
///
/// Codec support depends on the browser's WebCodecs implementation: Chromium is
/// fully supported; Safari/Firefox vary.
class MsgVideoTrimmerWeb extends VideoTrimmerPlatform {
  MsgVideoTrimmerWeb();

  /// Registers this class as the default [VideoTrimmerPlatform] on web.
  static void registerWith(Registrar registrar) {
    VideoTrimmerPlatform.instance = MsgVideoTrimmerWeb();
  }

  final StreamController<double> _progress =
      StreamController<double>.broadcast();
  final List<String> _objectUrls = <String>[];

  web.Worker? _worker;

  web.Worker _ensureWorker() {
    final existing = _worker;
    if (existing != null) return existing;

    final blob = web.Blob(
      <JSAny>[trimmerWorkerSource.toJS].toJS,
      web.BlobPropertyBag(type: 'text/javascript'),
    );
    final url = web.URL.createObjectURL(blob);
    final worker = web.Worker(
      url.toJS,
      web.WorkerOptions(type: 'module'),
    );
    // The worker keeps running after construction, so the script URL can be
    // released immediately.
    web.URL.revokeObjectURL(url);
    _worker = worker;
    return worker;
  }

  @override
  Future<void> loadVideo(String path) {
    final worker = _ensureWorker();
    final completer = Completer<void>();

    void handler(web.Event event) {
      final data = (event as web.MessageEvent).data as JSObject;
      final type = (data.getProperty('type'.toJS) as JSString?)?.toDart;
      if (type == 'loaded') {
        worker.removeEventListener('message', handler.toJS);
        completer.complete();
      } else if (type == 'error') {
        worker.removeEventListener('message', handler.toJS);
        final message =
            (data.getProperty('message'.toJS) as JSString?)?.toDart ??
                'load failed';
        completer.completeError(StateError(message));
      }
    }

    worker.addEventListener('message', handler.toJS);
    worker.postMessage(
      _jsObject(<String, Object?>{'cmd': 'load', 'url': path}),
    );
    return completer.future;
  }

  @override
  Future<String?> trimVideo({
    required int startTimeMs,
    required int endTimeMs,
    bool includeAudio = true,
  }) {
    final worker = _ensureWorker();
    final completer = Completer<String?>();

    void handler(web.Event event) {
      final data = (event as web.MessageEvent).data as JSObject;
      final type = (data.getProperty('type'.toJS) as JSString?)?.toDart;
      switch (type) {
        case 'progress':
          final value =
              (data.getProperty('value'.toJS) as JSNumber?)?.toDartDouble;
          if (value != null) _progress.add(value);
          break;
        case 'done':
          worker.removeEventListener('message', handler.toJS);
          final buffer = data.getProperty('buffer'.toJS) as JSArrayBuffer;
          final blob = web.Blob(
            <JSAny>[buffer].toJS,
            web.BlobPropertyBag(type: 'video/mp4'),
          );
          final url = web.URL.createObjectURL(blob);
          _objectUrls.add(url);
          completer.complete(url);
          break;
        case 'error':
          worker.removeEventListener('message', handler.toJS);
          final message =
              (data.getProperty('message'.toJS) as JSString?)?.toDart ??
                  'trim failed';
          completer.completeError(StateError(message));
          break;
      }
    }

    worker.addEventListener('message', handler.toJS);
    worker.postMessage(_jsObject(<String, Object?>{
      'cmd': 'trim',
      'startMs': startTimeMs,
      'endMs': endTimeMs,
      'includeAudio': includeAudio,
    }));
    return completer.future;
  }

  @override
  Future<void> clearCache() async {
    for (final url in _objectUrls) {
      web.URL.revokeObjectURL(url);
    }
    _objectUrls.clear();
  }

  @override
  Stream<double> get trimProgress => _progress.stream;

  JSObject _jsObject(Map<String, Object?> map) {
    final obj = JSObject();
    map.forEach((key, value) {
      obj.setProperty(key.toJS, _toJS(value));
    });
    return obj;
  }

  JSAny? _toJS(Object? value) {
    if (value == null) return null;
    if (value is String) return value.toJS;
    if (value is int) return value.toJS;
    if (value is double) return value.toJS;
    if (value is bool) return value.toJS;
    throw ArgumentError('Unsupported value for worker message: $value');
  }
}
