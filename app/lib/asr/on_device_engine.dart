import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import '../core/recitation_review.dart';
import 'engine.dart';

/// Locates (and downloads on first use) the ggml Whisper model file.
///
/// A download is shared by every screen, so pressing the microphone again, or
/// the download button in settings, joins the running download instead of
/// starting another. An interrupted download resumes where it stopped.
class ModelManager {
  ModelManager({required this.modelUrl, Future<Directory> Function()? storage})
      : _storage = storage ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _storage;

  /// Whisper fine-tuned on Quran recitation (tarteel-ai/whisper-base-ar-quran),
  /// converted to ggml by the "Recognition model" workflow and published as a
  /// release of this repository.
  static const quranModelUrl =
      'https://github.com/abdulrahmanahmedelabed-prog/quran-ai/releases/download/model-v2/ggml-quran-base.bin';

  /// Used when the Quran model is not available on the server.
  static const fallbackModel = WhisperModel.base;

  /// Smaller files are error pages, not models (the smallest is ~30 MB).
  static const _minModelBytes = 1 << 20;

  /// Progress of the running download, shared by every screen: null when
  /// none is running, -1 while the size is unknown, otherwise in [0, 1].
  static final ValueNotifier<double?> progress = ValueNotifier(null);

  static final Map<String, Future<String>> _running = {};

  /// A custom model URL from settings; empty uses [quranModelUrl], then
  /// [fallbackModel].
  final String modelUrl;

  List<String> get _candidates =>
      modelUrl.isNotEmpty ? [modelUrl] : [quranModelUrl, fallbackModel.modelUri.toString()];

  Future<File> _fileFor(String url) async {
    final dir = Directory('${(await _storage()).path}/models');
    await dir.create(recursive: true);
    final name = Uri.parse(url).pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => 'model.bin');
    return File('${dir.path}/${url.hashCode.toUnsigned(32).toRadixString(16)}-$name');
  }

  Future<String?> _existing() async {
    for (final url in _candidates) {
      final file = await _fileFor(url);
      if (await file.exists()) return file.path;
    }
    return null;
  }

  Future<bool> isDownloaded() async {
    try {
      return await _existing() != null;
    } catch (_) {
      // No storage directory (e.g. in tests): treat as not downloaded.
      return false;
    }
  }

  /// Deletes a model file that whisper.cpp could not load, so the next
  /// attempt downloads it again.
  Future<void> discard(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Removes files of earlier Quran model releases (model-v1 did not load),
  /// keeping [current].
  Future<void> _removeOldModels(String current) async {
    try {
      await for (final f in File(current).parent.list()) {
        if (f is File && f.path != current && f.path.contains('ggml-quran-base.bin')) await f.delete();
      }
    } catch (_) {}
  }

  /// Whether a download of this model is running (from any screen).
  bool get isDownloading => _running.containsKey(_candidates.join(' '));

  /// Returns the local model path, downloading it on first use.
  /// [onProgress] receives values in [0, 1] (null while the size is unknown).
  Future<String> ensure({void Function(double?)? onProgress}) async {
    final existing = await _existing();
    if (existing != null) {
      await _removeOldModels(existing);
      return existing;
    }
    void relay() {
      final p = progress.value;
      if (p != null) onProgress?.call(p < 0 ? null : p);
    }

    progress.addListener(relay);
    try {
      final key = _candidates.join(' ');
      final path = await (_running[key] ??= _downloadAny().whenComplete(() {
        _running.remove(key);
        progress.value = null;
      }));
      await _removeOldModels(path);
      return path;
    } finally {
      progress.removeListener(relay);
    }
  }

  Future<String> _downloadAny() async {
    progress.value = -1;
    for (final (i, url) in _candidates.indexed) {
      try {
        return await _download(url, await _fileFor(url));
      } on _ModelUnavailable {
        // Only a model missing from the server moves on to the next one; a
        // network error would fail there too, and the partial file of this
        // one is kept to resume.
        if (i == _candidates.length - 1) {
          throw const RecognitionException('نموذج التعرّف غير متاح للتنزيل الآن. حاول لاحقًا.');
        }
      }
    }
    throw StateError('no model candidates');
  }

  Future<String> _download(String url, File file) async {
    final partial = File('${file.path}.part');
    var received = await partial.exists() ? await partial.length() : 0;
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      if (received > 0) request.headers['Range'] = 'bytes=$received-';
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode == 416) {
        // The saved part doesn't fit the file on the server: start over.
        await partial.delete();
        client.close();
        return await _download(url, file);
      }
      if (response.statusCode == 404 || response.statusCode == 403 || response.statusCode == 410) {
        throw _ModelUnavailable();
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw RecognitionException('تعذّر تنزيل نموذج التعرّف (رمز ${response.statusCode}). حاول مرة أخرى.');
      }
      // A plain 200 means the server sent the whole file again.
      if (response.statusCode == 200) received = 0;
      final length = response.contentLength;
      final total = length == null ? 0 : received + length;
      final sink = partial.openWrite(mode: received > 0 ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          progress.value = total > 0 ? received / total : -1;
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received < total) throw const RecognitionException(_interrupted);
      if (received < _minModelBytes) {
        await partial.delete();
        throw _ModelUnavailable();
      }
      await partial.rename(file.path);
      return file.path;
    } on RecognitionException {
      rethrow;
    } on _ModelUnavailable {
      rethrow;
    } catch (e) {
      // Say "no internet" only when the server's name couldn't be looked up;
      // other failures happen on working connections too.
      if (received == 0 && '$e'.contains('Failed host lookup')) {
        throw const RecognitionException(
            'لا يوجد اتصال بالإنترنت لتنزيل نموذج التعرّف (مرة واحدة فقط، ثم يعمل دون إنترنت).');
      }
      throw RecognitionException(received == 0 ? 'تعذّر الوصول إلى خادم التنزيل. حاول مرة أخرى.' : _interrupted);
    } finally {
      client.close();
    }
  }

  static const _interrupted = 'انقطع تنزيل نموذج التعرّف. اضغط مرة أخرى ليكمل من حيث توقف.';
}

class _ModelUnavailable implements Exception {}

/// Runs Whisper on the phone with whisper.cpp: no server needed, works
/// offline after the model's one-time download.
class OnDeviceEngine implements RecognitionEngine {
  OnDeviceEngine({required this.models, this.onModelProgress, this.onModelLoading});

  final ModelManager models;

  /// Model download progress, for the first run.
  final void Function(double?)? onModelProgress;

  /// Called once the model is on the device and is being loaded into memory
  /// (after a download this replaces the finished progress).
  final VoidCallback? onModelLoading;

  /// Loading takes seconds; anything near this means it is stuck.
  static const loadTimeout = Duration(minutes: 2);

  final Microphone _mic = Microphone();
  final StreamController<String> _transcripts = StreamController.broadcast();
  WhisperLiveSession? _session;
  StreamSubscription<String>? _partials;
  StreamSubscription<List<int>>? _audio;
  String _last = '';
  bool _disposed = false;

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
    _checkNotDisposed();
    onModelLoading?.call();
    final WhisperLiveSession session;
    try {
      session = _session = await startWhisperLiveSession(
        modelPath: path,
        lang: 'ar',
        suppressNonSpeechTokens: true,
        // Sessions are started and stopped often; avoid reloading each time.
        keepModelLoaded: true,
      ).timeout(loadTimeout);
    } on TimeoutException {
      throw const RecognitionException('تعذّر تشغيل نموذج التعرّف على هذا الجهاز (استغرق وقتًا طويلًا). أعد المحاولة.');
    } catch (e) {
      if ('$e'.contains('failed to load model')) {
        await models.discard(path);
        throw const RecognitionException('ملف نموذج التعرّف لا يعمل فحُذف. اضغط الميكروفون ليُنزَّل من جديد.');
      }
      throw RecognitionException('تعذّر تشغيل نموذج التعرّف: $e');
    }
    if (_disposed) {
      _session = null;
      await session.stop();
      _checkNotDisposed();
    }
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

  /// The screen may close during the model download; the microphone must
  /// not open after that.
  void _checkNotDisposed() {
    if (_disposed) throw const RecognitionException('أُلغي بدء التسميع.');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _audio?.cancel();
    await _partials?.cancel();
    if (_session != null) await _session!.stop();
    await _mic.dispose();
    await _transcripts.close();
  }
}
