import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../asr/engine.dart';
import '../../core/ayah_search.dart';
import '../../ui/theme.dart';
import '../recite/recite_page.dart';

/// Recite any passage and find where it is in the Quran.
class VoiceSearchPage extends StatefulWidget {
  const VoiceSearchPage({super.key});

  @override
  State<VoiceSearchPage> createState() => _VoiceSearchPageState();
}

class _VoiceSearchPageState extends State<VoiceSearchPage> {
  RecognitionEngine? _engine;
  StreamSubscription<String>? _sub;
  bool _listening = false;
  bool _busy = false;
  String _transcript = '';
  String? _error;
  List<SearchHit> _hits = const [];
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start building the index before the first search needs it.
    AppScope.of(context).searchIndex;
  }

  Future<void> _search(String text) async {
    final index = await AppScope.of(context).searchIndex;
    if (!mounted) return;
    setState(() => _hits = index.search(text));
  }

  Future<void> _toggle() async {
    if (_listening) {
      setState(() => _busy = true);
      final text = await _engine!.stop();
      await _sub?.cancel();
      await _engine!.dispose();
      _engine = null;
      _debounce?.cancel();
      if (!mounted) return;
      setState(() {
        _listening = false;
        _busy = false;
        if (text.isNotEmpty) _transcript = text;
      });
      _search(_transcript);
      return;
    }
    final engine = _engine = AppScope.of(context).createEngine();
    setState(() {
      _busy = true;
      _error = null;
      _transcript = '';
      _hits = const [];
    });
    _sub = engine.transcripts.listen((text) {
      setState(() => _transcript = text);
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), () => _search(text));
    });
    try {
      await engine.start();
      setState(() {
        _listening = true;
        _busy = false;
      });
    } catch (e) {
      await _sub?.cancel();
      await engine.dispose();
      _engine = null;
      setState(() {
        _busy = false;
        _error = e is RecognitionException ? e.message : '$e';
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quran = AppScope.of(context).quran;
    return Scaffold(
      appBar: AppBar(title: const Text('ابحث بصوتك')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'اقرأ أي آية تتذكرها وسنجد لك موضعها في المصحف',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline, fontSize: 16),
          ),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 96,
              height: 96,
              child: FloatingActionButton.large(
                heroTag: null,
                shape: const CircleBorder(),
                backgroundColor: _listening ? scheme.error : scheme.primary,
                foregroundColor: _listening ? scheme.onError : scheme.onPrimary,
                onPressed: _busy ? null : _toggle,
                child: _busy
                    ? CircularProgressIndicator(color: scheme.onPrimary)
                    : Icon(_listening ? Icons.stop_rounded : Icons.mic, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_error != null) Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
          if (_transcript.isNotEmpty)
            Text('«$_transcript»', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 16),
          if (!_listening && !_busy && _transcript.isNotEmpty && _hits.isEmpty)
            const Text('لم نعثر على الآية، حاول قراءة عدد أكبر من الكلمات.', textAlign: TextAlign.center),
          for (final hit in _hits)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: Text(
                  quran.ayahText(hit.surah, hit.ayah),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'AmiriQuran', fontSize: 20, height: 1.9),
                ),
                subtitle: Text(
                  'سورة ${quran.surah(hit.surah).name} · الآية ${arabicNumber(hit.ayah)}'
                  ' · تطابق ${arabicNumber((hit.score * 100).round())}٪',
                ),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RecitePage(surah: quran.surah(hit.surah), fromAyah: hit.ayah),
                )),
              ),
            ),
        ],
      ),
    );
  }
}
