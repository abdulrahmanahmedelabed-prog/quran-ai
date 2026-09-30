import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/alignment.dart';

enum EngineKind { server, onDevice }

/// How forgiving mistake detection is.
enum Strictness {
  lenient('متساهل', 0.65),
  normal('عادي', 0.8),
  strict('دقيق', 0.9);

  const Strictness(this.label, this.threshold);

  final String label;
  final double threshold;
}

class Reciter {
  const Reciter(this.id, this.name);

  /// Folder name on everyayah.com.
  final String id;
  final String name;
}

const reciters = [
  Reciter('Husary_128kbps', 'محمود خليل الحصري'),
  Reciter('Minshawy_Murattal_128kbps', 'محمد صديق المنشاوي'),
  Reciter('Abdul_Basit_Murattal_192kbps', 'عبد الباسط عبد الصمد'),
  Reciter('Abdurrahmaan_As-Sudais_192kbps', 'عبد الرحمن السديس'),
  Reciter('MaherAlMuaiqly128kbps', 'ماهر المعيقلي'),
  Reciter('Ghamadi_40kbps', 'سعد الغامدي'),
];

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async => AppSettings(await SharedPreferences.getInstance());

  /// On the phone by default: it works without setting up a server.
  EngineKind get engine =>
      EngineKind.values.asNameMap()[_prefs.getString('engine')] ?? EngineKind.onDevice;
  set engine(EngineKind v) => _set('engine', v.name);

  /// Base URL of the recognition server, e.g. `https://asr.example.com`.
  /// Empty until the user sets up a server.
  String get serverUrl => _prefs.getString('serverUrl') ?? '';
  set serverUrl(String v) => _set('serverUrl', v.trim());

  String get apiKey => _prefs.getString('apiKey') ?? '';
  set apiKey(String v) => _set('apiKey', v.trim());

  /// URL of a ggml Whisper model for on-device recognition. Empty uses the
  /// generic multilingual `base` model.
  String get modelUrl => _prefs.getString('modelUrl') ?? '';
  set modelUrl(String v) => _set('modelUrl', v.trim());

  Strictness get strictness =>
      Strictness.values.asNameMap()[_prefs.getString('strictness')] ?? Strictness.normal;
  set strictness(Strictness v) => _set('strictness', v.name);

  AlignerConfig get alignerConfig => AlignerConfig(threshold: strictness.threshold);

  double get fontSize => _prefs.getDouble('fontSize') ?? 28;
  set fontSize(double v) {
    _prefs.setDouble('fontSize', v);
    notifyListeners();
  }

  String get reciterId {
    final id = _prefs.getString('reciter');
    // Falls back if the saved reciter was removed from the list.
    return reciters.any((r) => r.id == id) ? id! : reciters.first.id;
  }
  set reciterId(String v) => _set('reciter', v);

  /// Start recitation sessions with the text hidden (memorization test).
  bool get hideByDefault => _prefs.getBool('hideByDefault') ?? false;
  set hideByDefault(bool v) {
    _prefs.setBool('hideByDefault', v);
    notifyListeners();
  }

  /// Color mistakes on the words themselves while reciting. Off by default:
  /// mistakes go quietly into the ayah's margin instead, so the reciter isn't
  /// interrupted.
  bool get mistakesInText => _prefs.getBool('mistakesInText') ?? false;
  set mistakesInText(bool v) {
    _prefs.setBool('mistakesInText', v);
    notifyListeners();
  }

  /// Show surahs on Madinah Mushaf pages (15 lines) rather than as
  /// continuous text.
  bool get mushafPages => _prefs.getBool('mushafPages') ?? true;
  set mushafPages(bool v) {
    _prefs.setBool('mushafPages', v);
    notifyListeners();
  }

  /// Color tajweed rulings in the mushaf (Plus).
  bool get tajweedColors => _prefs.getBool('tajweedColors') ?? true;
  set tajweedColors(bool v) {
    _prefs.setBool('tajweedColors', v);
    notifyListeners();
  }

  void _set(String key, String value) {
    _prefs.setString(key, value);
    notifyListeners();
  }
}
