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

/// Removes annotations recognizers emit for non-speech sounds ([موسيقى]),
/// and decoding loops (see [collapseLoops]).
String cleanTranscript(String text) => collapseLoops(
  text.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)|\*[^*]*\*'), ' ').replaceAll(RegExp(' {2,}'), ' ').trim(),
);

/// Cuts a phrase of two or more words repeated three or more times in a row
/// back to one occurrence, and drops what follows it. On audio cut mid-word,
/// Whisper sometimes loops ("لم يلد ولا لم يلد ولا لم يلد ولا…") until the
/// next partial corrects it; the Quran never repeats a phrase like that, and
/// the looping tail would only mislead the tracker.
String collapseLoops(String text) {
  // Words are separated by spaces only (2:72 has a thin space inside a word).
  final words = text.split(RegExp(r' +')).where((w) => w.isNotEmpty).toList();
  for (var start = 0; start < words.length; start++) {
    for (var n = 2; start + 3 * n <= words.length; n++) {
      bool same(int k) {
        for (var i = 0; i < n; i++) {
          if (words[start + i] != words[start + k * n + i]) return false;
        }
        return true;
      }

      if (same(1) && same(2)) return words.take(start + n).join(' ');
    }
  }
  return text;
}

/// Microphone capture as 16 kHz mono PCM16, the format Whisper expects.
class Microphone {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<double> _levels = StreamController.broadcast();

  static const sampleRate = 16000;

  Stream<double> get levels => _levels.stream;

  /// Asks for microphone access (the system prompt appears on first use).
  /// Engines call this before any slow setup, so the prompt shows at once.
  Future<void> ensurePermission() async {
    if (!await _recorder.hasPermission()) {
      throw const RecognitionException(
        'التطبيق يحتاج إذن الميكروفون ليسمع تلاوتك. فعّله من إعدادات الجوال ← التطبيقات ← قرآن AI ← الأذونات.',
      );
    }
  }

  Future<Stream<Uint8List>> start() async {
    await ensurePermission();
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1, noiseSuppress: true),
    );
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
