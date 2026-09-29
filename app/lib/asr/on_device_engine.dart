import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../core/recitation_review.dart';
import 'engine.dart';

/// Locates (and downloads on first use) the ggml Whisper model file.
class ModelManager {
  ModelManager({required this.modelUrl});

  /// URL of a custom ggml model, e.g. the Quran fine-tuned Whisper converted
  /// with `tools/convert_model_to_ggml.sh`. Empty selects the generic
  /// multilingual `base` model.
  final String modelUrl;

  static const fallbackModel = WhisperModel.base;

  Future<File> _customFile() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
    await dir.create(recursive: true);
    final name = Uri.parse(modelUrl).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'model.bin');
    return File('${dir.path}/${modelUrl.hashCode.toUnsigned(32).toRadixString(16)}-$name');
  }

  Future<bool> isDownloaded() async {
    if (modelUrl.isEmpty) {
      return File(await WhisperController().getPath(fallbackModel)).exists();
    }
    return (await _customFile()).exists();
  }

  /// Returns the local model path, downloading it if needed.
  /// [onProgress] receives values in [0, 1] when the size is known.
  Future<String> ensure({void Function(double)? onProgress}) async {
    if (modelUrl.isEmpty) {
      return WhisperController().downloadModel(fallbackModel);
    }
    final file = await _customFile();
    if (await file.exists()) return file.path;

    final client = http.Client();
    final partial = File('${file.path}.part');
    try {
      final response = await client.send(http.Request('GET', Uri.parse(modelUrl)));
      if (response.statusCode != 200) {
        throw RecognitionException('فشل تنزيل النموذج (${response.statusCode}).');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = partial.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
      await partial.rename(file.path);
      return file.path;
    } on SocketException {
      throw const RecognitionException('لا يوجد اتصال بالإنترنت لتنزيل النموذج.');
    } finally {
      client.close();
      if (await partial.exists()) await partial.delete();
    }
  }
}

/// Runs Whisper on the phone with whisper.cpp: private and works offline.
class OnDeviceEngine implements RecognitionEngine {
  OnDeviceEngine({required this.models});

  final ModelManager models;
  final Microphone _mic = Microphone();
  final StreamController<String> _transcripts = StreamController.broadcast();
  WhisperLiveSession? _session;
  StreamSubscription<String>? _partials;
  StreamSubscription<List<int>>? _audio;
  String _last = '';

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Stream<double> get levels => _mic.levels;

  /// The live whisper.cpp session reports text only.
  @override
  List<TimedWord> get timedWords => const [];

  @override
  Future<void> start() async {
    final path = await models.ensure();
    final session = _session = await startWhisperLiveSession(
      modelPath: path,
      lang: 'ar',
      suppressNonSpeechTokens: true,
      // Sessions are started and stopped often; avoid reloading each time.
      keepModelLoaded: true,
    );
    _partials = session.partials.listen((text) {
      _last = cleanTranscript(text);
      _transcripts.add(_last);
    });
    final audio = await _mic.start();
    _audio = audio.listen((chunk) => session.feed(chunk));
  }

  @override
  Future<String> stop() async {
    await _audio?.cancel();
    await _mic.stop();
    final session = _session;
    if (session == null) return _last;
    final text = cleanTranscript(await session.stop());
    await _partials?.cancel();
    _session = null;
    return text.isEmpty ? _last : text;
  }

  @override
  Future<void> dispose() async {
    await _audio?.cancel();
    await _partials?.cancel();
    if (_session != null) await _session!.stop();
    await _mic.dispose();
    await _transcripts.close();
  }
}
