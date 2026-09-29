import 'ffmpeg_session.dart';
import 'return_code.dart';

/// Conversion is unavailable: every command fails, so callers fall back to
/// using their input as is (whisper_ggml then transcribes WAV input directly).
class FFmpegKit {
  static Future<FFmpegSession> execute(String command) async => const FFmpegSession(ReturnCode(1));
}
