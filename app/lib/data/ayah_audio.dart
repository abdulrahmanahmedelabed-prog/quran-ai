import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Reciter audio for one ayah. Each ayah is saved on the device the first
/// time it plays, and later plays come from that file, without the internet.
class AyahAudio {
  AyahAudio._(this.url, this.file);

  final Uri url;

  /// Where the ayah is (or will be) saved; null when there is no storage.
  final File? file;

  static Directory? _root;

  static Future<AyahAudio> of(String reciter, int surah, int ayah) async {
    String pad(int n) => n.toString().padLeft(3, '0');
    final name = '${pad(surah)}${pad(ayah)}.mp3';
    final url = Uri.parse('https://everyayah.com/data/$reciter/$name');
    try {
      _root ??= Directory('${(await getApplicationSupportDirectory()).path}/audio');
      final dir = Directory('${_root!.path}/$reciter');
      await dir.create(recursive: true);
      return AyahAudio._(url, File('${dir.path}/$name'));
    } catch (_) {
      return AyahAudio._(url, null);
    }
  }

  /// Whether the ayah is already saved on the device.
  bool get isSaved => file?.existsSync() ?? false;

  /// Plays from the saved file, or streams while saving it.
  AudioSource get source {
    final file = this.file;
    if (file == null) return AudioSource.uri(url);
    if (file.existsSync()) return AudioSource.file(file.path);
    // Stable in practice; saves the file as it plays, once it is complete.
    // ignore: experimental_member_use
    return LockCachingAudioSource(url, cacheFile: file);
  }
}
