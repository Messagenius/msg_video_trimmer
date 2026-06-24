import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:msg_video_trimmer/msg_video_trimmer.dart';
import 'package:video_player/video_player.dart';

import 'preview_controller.dart';

void main() => runApp(const TrimmerApp());

class TrimmerApp extends StatelessWidget {
  const TrimmerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'msg_video_trimmer',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const TrimmerPage(),
    );
  }
}

class TrimmerPage extends StatefulWidget {
  const TrimmerPage({super.key});

  @override
  State<TrimmerPage> createState() => _TrimmerPageState();
}

class _TrimmerPageState extends State<TrimmerPage> {
  final _trimmer = VideoTrimmer();

  String? _sourceLabel;
  String? _outputPath;
  bool _includeAudio = true;
  bool _busy = false;
  double _progress = 0;
  String? _error;

  final _startController = TextEditingController(text: '2000');
  final _endController = TextEditingController(text: '5000');

  VideoPlayerController? _player;

  @override
  void initState() {
    super.initState();
    _trimmer.trimProgress.listen((value) {
      if (mounted) setState(() => _progress = value);
    });
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: kIsWeb,
    );
    if (result == null) return;
    final file = result.files.single;

    // Web has no path; create a blob URL from the picked bytes.
    final String source;
    if (kIsWeb) {
      final bytes = file.bytes;
      if (bytes == null) return;
      source = Uri.dataFromBytes(bytes, mimeType: 'video/mp4').toString();
    } else {
      source = file.path!;
    }

    setState(() {
      _sourceLabel = file.name;
      _outputPath = null;
      _error = null;
    });
    try {
      await _trimmer.loadVideo(source);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _trim() async {
    final start = int.tryParse(_startController.text);
    final end = int.tryParse(_endController.text);
    if (start == null || end == null) {
      setState(() => _error = 'Enter valid start/end milliseconds');
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _outputPath = null;
    });
    try {
      final out = await _trimmer.trimVideo(
        startTimeMs: start,
        endTimeMs: end,
        includeAudio: _includeAudio,
      );
      setState(() => _outputPath = out);
      await _preview(out);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(String? path) async {
    if (path == null) return;
    await _player?.dispose();
    _player = null;
    try {
      final controller = createPreviewController(
        path,
        isBlob: path.startsWith('blob:') || path.startsWith('data:'),
      );
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() => _player = controller);
    } catch (_) {
      // Preview is best-effort (e.g. video_player has no Windows backend).
      if (mounted) setState(() => _player = null);
    }
  }

  Future<void> _clearCache() async {
    await _trimmer.clearCache();
    await _player?.dispose();
    setState(() {
      _outputPath = null;
      _player = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('msg_video_trimmer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.video_library),
              label: const Text('Pick video'),
            ),
            if (_sourceLabel != null) ...[
              const SizedBox(height: 8),
              Text('Source: $_sourceLabel', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Start (ms)', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'End (ms)', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Include audio'),
              value: _includeAudio,
              onChanged:
                  _busy ? null : (v) => setState(() => _includeAudio = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (_busy || _sourceLabel == null) ? null : _trim,
              icon: const Icon(Icons.content_cut),
              label: const Text('Trim'),
            ),
            const SizedBox(height: 16),
            if (_busy) ...[
              LinearProgressIndicator(value: _progress / 100),
              const SizedBox(height: 4),
              Text('${_progress.toStringAsFixed(0)}%'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_outputPath != null) ...[
              const SizedBox(height: 16),
              Text('Output: $_outputPath', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              if (_player?.value.isInitialized ?? false)
                AspectRatio(
                  aspectRatio: _player!.value.aspectRatio,
                  child: VideoPlayer(_player!),
                ),
              TextButton.icon(
                onPressed: _clearCache,
                icon: const Icon(Icons.delete),
                label: const Text('Clear cache'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
