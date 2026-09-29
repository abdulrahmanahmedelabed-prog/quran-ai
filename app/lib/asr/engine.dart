import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

import '../core/recitation_review.dart';

/// Something that listens to the microphone and transcribes recitation.
abstract class RecognitionEngine {
  /// Full transcript of the session so far; later values may revise the tail.
  Stream<String> get transcripts;

  /// Microphone level in [0, 1] for visual feedback.
  Stream<double> get levels;

  /// Final words with timings, when the recognizer provides them (used to
  /// check madd lengths). Complete once [stop] has returned.
  List<TimedWord> get timedWords;

  /// Starts listening. Throws [RecognitionException] with a user-facing
  /// message on failure.
  Future<void> start();

  /// Stops listening and returns the final transcript.
  Future<String> stop();

  Future<void> dispose();
}

class RecognitionException implements Exception {
  const RecognitionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Removes annotations recognizers emit for non-speech sounds ([موسيقى]).
String cleanTranscript(String text) =>
    text.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*'), ' ').trim();

/// Microphone capture as 16 kHz mono PCM16, the format Whisper expects.
class Microphone {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _levels = StreamController.broadcast();

  static const sampleRate = 16000;

  Stream<double> get levels => _levels.stream;

  Future<Stream<Uint8List>> start() async {
    if (!await _recorder.hasPermission()) {
      throw const RecognitionException('يرجى السماح للتطبيق باستخدام الميكروفون من الإعدادات.');
    }
    final stream = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      noiseSuppress: true,
    ));
    return stream.map((chunk) {
      _levels.add(_level(chunk));
      return chunk;
    });
  }

  Future<void> stop() async {
    if (await _recorder.isRecording()) await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
    await _levels.close();
  }

  static double _level(Uint8List chunk) {
    final samples = chunk.buffer.asInt16List(chunk.offsetInBytes, chunk.lengthInBytes ~/ 2);
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    final rms = math.sqrt(sum / samples.length) / 32768;
    // Map roughly -50 dB..0 dB to 0..1.
    final db = 20 * math.log(rms + 1e-9) / math.ln10;
    return ((db + 50) / 50).clamp(0.0, 1.0);
  }
}
