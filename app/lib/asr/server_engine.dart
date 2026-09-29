import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/recitation_review.dart';
import 'engine.dart';

/// Streams microphone audio to the recognition server (see `server/`) over a
/// WebSocket and assembles its per-segment results into one transcript.
class ServerEngine implements RecognitionEngine {
  ServerEngine({required this.baseUrl, this.apiKey = ''});

  final String baseUrl;
  final String apiKey;

  final Microphone _mic = Microphone();
  final StreamController<String> _transcripts = StreamController.broadcast();
  final Map<int, String> _finals = {};
  final Map<int, List<TimedWord>> _finalWords = {};
  final Completer<void> _done = Completer();
  WebSocketChannel? _channel;
  StreamSubscription<List<int>>? _audio;
  int? _partialSegment;
  String _partial = '';

  @override
  Stream<String> get transcripts => _transcripts.stream;

  @override
  Stream<double> get levels => _mic.levels;

  @override
  List<TimedWord> get timedWords {
    final ids = _finalWords.keys.toList()..sort();
    return [for (final id in ids) ..._finalWords[id]!];
  }

  String get transcript {
    final ids = _finals.keys.toList()..sort();
    return [
      for (final id in ids) _finals[id]!,
      if (_partialSegment != null && !_finals.containsKey(_partialSegment)) _partial,
    ].where((s) => s.isNotEmpty).join(' ');
  }

  Uri get _streamUri {
    final base = Uri.parse(baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/v1/stream',
      queryParameters: apiKey.isEmpty ? null : {'key': apiKey},
    );
  }

  @override
  Future<void> start() async {
    await _mic.ensurePermission();
    final ready = Completer<void>();
    try {
      final channel = _channel = WebSocketChannel.connect(_streamUri);
      await channel.ready.timeout(const Duration(seconds: 8));
      channel.stream.listen(
        (message) {
          if (message is! String) return;
          final event = jsonDecode(message) as Map<String, dynamic>;
          switch (event['type']) {
            case 'ready':
              if (!ready.isCompleted) ready.complete();
            case 'partial':
              _partialSegment = event['segment'] as int;
              _partial = cleanTranscript(event['text'] as String);
              _transcripts.add(transcript);
            case 'final':
              final segment = event['segment'] as int;
              _finals[segment] = cleanTranscript(event['text'] as String);
              final words = event['words'] as List?;
              if (words != null) {
                _finalWords[segment] = [for (final w in words) TimedWord.fromJson(w as Map<String, dynamic>)];
              }
              _transcripts.add(transcript);
            case 'done':
              if (!_done.isCompleted) _done.complete();
          }
        },
        onError: (Object e) {
          if (!ready.isCompleted) ready.completeError(e);
          if (!_done.isCompleted) _done.complete();
        },
        onDone: () {
          if (!ready.isCompleted) {
            ready.completeError(const RecognitionException('رفض الخادم الاتصال. تحقق من مفتاح الوصول.'));
          }
          if (!_done.isCompleted) _done.complete();
        },
      );
      await ready.future.timeout(const Duration(seconds: 30));
    } on RecognitionException {
      rethrow;
    } catch (_) {
      await _channel?.sink.close();
      throw RecognitionException('تعذر الاتصال بخادم التعرف على\n$baseUrl');
    }
    final audio = await _mic.start();
    _audio = audio.listen(_channel!.sink.add);
  }

  @override
  Future<String> stop() async {
    await _audio?.cancel();
    await _mic.stop();
    final channel = _channel;
    if (channel != null) {
      channel.sink.add(jsonEncode({'type': 'stop'}));
      // The server transcribes any open segment before it sends "done".
      await _done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      await channel.sink.close();
    }
    return transcript;
  }

  @override
  Future<void> dispose() async {
    await _audio?.cancel();
    await _channel?.sink.close();
    await _mic.dispose();
    await _transcripts.close();
  }
}
