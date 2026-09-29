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

  /// Whisper fine-tuned on Quran recitation (tarteel-ai/whisper-base-ar-quran),
  /// converted to ggml by the "Recognition model" workflow and published as a
  /// release of this repository.
  static const quranModelUrl =
      'https://github.com/abdulrahmanahmedelabed-prog/quran-ai/releases/download/model-v1/ggml-quran-base.bin';

  /// Used when the Quran model can't be downloaded.
  static const fallbackModel = WhisperModel.base;

  /// A custom model URL from settings; empty uses [quranModelUrl], then
  /// [fallbackModel].
  final String modelUrl;

  List<String> get _candidates =>
      modelUrl.isNotEmpty ? [modelUrl] : [quranModelUrl, fallbackModel.modelUri.toString()];

  Future<File> _fileFor(String url) async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
    await dir.create(recursive: true);
    final name = Uri.parse(url).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'model.bin');
    return File('${dir.path}/${url.hashCode.toUnsigned(32).toRadixString(16)}-$name');
  }

  Future<bool> isDownloaded() async {
    try {
      for (final url in _candidates) {
        if (await (await _fileFor(url)).exists()) return true;
      }
    } catch (_) {
      // No storage directory (e.g. in tests): treat as not downloaded.
    }
    return false;
  }

  /// Returns the local model path, downloading it on first use.
  /// [onProgress] receives values in [0, 1] (null while the size is unknown).
  Future<String> ensure({void Function(double?)? onProgress}) async {
    for (final url in _candidates) {
      final file = await _fileFor(url);
      if (await file.exists()) return file.path;
    }
    RecognitionException? lastError;
    for (final url in _candidates) {
      try {
        return await _download(url, await _fileFor(url), onProgress);
      } on RecognitionException catch (e) {
        lastError = e; // try the next candidate
      }
    }
    throw lastError ?? const RecognitionException('تعذر تنزيل نموذج التعرّف.');
  }

  Future<String> _download(String url, File file, void Function(double?)? onProgress) async {
    final client = http.Client();
    final partial = File('${file.path}.part');
    try {
      onProgress?.call(null);
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw RecognitionException('فشل تنزيل نموذج التعرّف (${response.statusCode}).');
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
      throw const RecognitionException('لا يوجد اتصال بالإنترنت لتنزيل نموذج التعرّف (مرة واحدة فقط).');
    } on http.ClientException {
      throw const RecognitionException('انقطع تنزيل نموذج التعرّف، حاول مرة أخرى.');
    } finally {
      client.close();
      if (await partial.exists()) await partial.delete();
    }
  }
}

/// Runs Whisper on the phone with whisper.cpp: no server needed, works
/// offline after the model's one-time download.
class OnDeviceEngine implements RecognitionEngine {
  OnDeviceEngine({required this.models, this.onModelProgress});

  final ModelManager models;

  /// Model download progress, for the first run.
  final void Function(double?)? onModelProgress;

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
    // Ask for the microphone first so the prompt isn't hidden behind the
    // model download.
    await _mic.ensurePermission();
    final path = await models.ensure(onProgress: onModelProgress);
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
