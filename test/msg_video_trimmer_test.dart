import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:msg_video_trimmer/msg_video_trimmer.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records calls so we can assert the public API forwards arguments correctly.
class _FakeVideoTrimmerPlatform extends VideoTrimmerPlatform
    with MockPlatformInterfaceMixin {
  final List<String> loaded = <String>[];
  final List<Map<String, Object?>> trims = <Map<String, Object?>>[];
  int clearCount = 0;
  final _progress = StreamController<double>.broadcast();

  @override
  Future<void> loadVideo(String path) async => loaded.add(path);

  @override
  Future<String?> trimVideo({
    required int startTimeMs,
    required int endTimeMs,
    bool includeAudio = true,
  }) async {
    trims.add({
      'startTimeMs': startTimeMs,
      'endTimeMs': endTimeMs,
      'includeAudio': includeAudio,
    });
    return 'video_trimmer_123.mp4';
  }

  @override
  Future<void> clearCache() async => clearCount++;

  @override
  Stream<double> get trimProgress => _progress.stream;

  void emit(double value) => _progress.add(value);
}

void main() {
  late _FakeVideoTrimmerPlatform fake;
  late VideoTrimmer trimmer;

  setUp(() {
    fake = _FakeVideoTrimmerPlatform();
    VideoTrimmerPlatform.instance = fake;
    trimmer = VideoTrimmer();
  });

  test('loadVideo forwards the path', () async {
    await trimmer.loadVideo('/tmp/in.mp4');
    expect(fake.loaded, ['/tmp/in.mp4']);
  });

  test('trimVideo forwards arguments and returns the output path', () async {
    final out = await trimmer.trimVideo(
      startTimeMs: 1000,
      endTimeMs: 4000,
      includeAudio: false,
    );
    expect(out, 'video_trimmer_123.mp4');
    expect(fake.trims.single, {
      'startTimeMs': 1000,
      'endTimeMs': 4000,
      'includeAudio': false,
    });
  });

  test('trimVideo defaults includeAudio to true', () async {
    await trimmer.trimVideo(startTimeMs: 0, endTimeMs: 1000);
    expect(fake.trims.single['includeAudio'], true);
  });

  test('clearCache delegates to the platform', () async {
    await trimmer.clearCache();
    expect(fake.clearCount, 1);
  });

  test('trimProgress surfaces platform progress events', () async {
    final events = <double>[];
    final sub = trimmer.trimProgress.listen(events.add);
    fake
      ..emit(0)
      ..emit(50)
      ..emit(100);
    await Future<void>.delayed(Duration.zero);
    expect(events, [0, 50, 100]);
    await sub.cancel();
  });
}
