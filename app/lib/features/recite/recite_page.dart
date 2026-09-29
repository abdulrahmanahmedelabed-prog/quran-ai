import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../app_scope.dart';
import '../../core/recitation_tracker.dart';
import '../../data/quran.dart';
import '../../ui/theme.dart';
import 'ayah_margin_sheet.dart';
import 'recite_controller.dart';
import 'session_summary.dart';

class RecitePage extends StatefulWidget {
  const RecitePage({super.key, required this.surah, this.fromAyah = 1});

  final Surah surah;
  final int fromAyah;

  @override
  State<RecitePage> createState() => _RecitePageState();
}

class _RecitePageState extends State<RecitePage> {
  late final ReciteController _c;
  final AudioPlayer _player = AudioPlayer();
  final ScrollController _scroll = ScrollController();
  late final Map<int, GlobalKey> _ayahKeys;
  late final List<List<int>> _wordsByAyah;
  StreamSubscription<int?>? _indexSub;

  /// Ayah being played by the reciter audio, if any.
  int? _playingAyah;
  int _playFrom = 1;
  int? _scrolledTo;

  @override
  void initState() {
    super.initState();
    _ayahKeys = {for (var a = 1; a <= widget.surah.ayahCount; a++) a: GlobalKey()};
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.fromAyah > 1) _scrollToAyah(widget.fromAyah, animate: false);
    });
  }

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _c = ReciteController(services: AppScope.of(context), surah: widget.surah, fromAyah: widget.fromAyah);
    _c.addListener(_onControllerChanged);
    _wordsByAyah = List.generate(widget.surah.ayahCount, (_) => <int>[]);
    for (var i = 0; i < _c.words.length; i++) {
      _wordsByAyah[_c.words[i].ayah - 1].add(i);
    }
  }

  void _onControllerChanged() {
    if (_c.isListening && _c.currentAyah != _scrolledTo) _scrollToAyah(_c.currentAyah);
  }

  /// Brings [ayah] into view. Ayahs are built lazily, so one far away has no
  /// context yet: jump to its estimated position first, then align it once
  /// it has been built.
  void _scrollToAyah(int ayah, {bool animate = true, int attempts = 3}) {
    _scrolledTo = ayah;
    final ctx = _ayahKeys[ayah]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.25,
        duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
        curve: Curves.easeOut,
      );
      return;
    }
    if (attempts == 0 || !_scroll.hasClients) return;
    final position = _scroll.position;
    final share = _c.firstWordOf(ayah) / _c.words.length;
    position.jumpTo((position.maxScrollExtent * share).clamp(0, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToAyah(ayah, animate: false, attempts: attempts - 1);
    });
  }

  @override
  void dispose() {
    _indexSub?.cancel();
    _player.dispose();
    _scroll.dispose();
    _c.removeListener(_onControllerChanged);
    _c.dispose();
    super.dispose();
  }

  Future<void> _toggleMic() async {
    if (_c.isListening) {
      final result = await _c.stop();
      if (result != null && mounted && result.stats.recited > 0) {
        await showSessionSummary(context, result);
      }
    } else {
      await _stopAudio();
      await _c.start();
    }
  }

  Future<void> _playFromAyah(int ayah) async {
    final reciter = AppScope.of(context).settings.reciterId;
    await _c.stop();
    String pad(int n) => n.toString().padLeft(3, '0');
    final sources = [
      for (var a = ayah; a <= widget.surah.ayahCount; a++)
        AudioSource.uri(Uri.parse('https://everyayah.com/data/$reciter/${pad(widget.surah.number)}${pad(a)}.mp3')),
    ];
    _playFrom = ayah;
    _indexSub?.cancel();
    _indexSub = _player.currentIndexStream.listen((i) {
      if (i == null) return;
      setState(() => _playingAyah = _playFrom + i);
      _scrollToAyah(_playFrom + i);
    });
    try {
      await _player.setAudioSources(sources);
      setState(() => _playingAyah = ayah);
      await _player.play();
      // play() completes when playback stops or the playlist ends.
      if (mounted && _player.processingState == ProcessingState.completed) {
        setState(() => _playingAyah = null);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playingAyah = null);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذر تشغيل التلاوة. تحقق من الاتصال بالإنترنت.')));
      }
    }
  }

  Future<void> _stopAudio() async {
    await _player.stop();
    if (mounted) setState(() => _playingAyah = null);
  }

  void _showAyahSheet(int ayah) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => AyahMarginSheet(
        controller: _c,
        ayah: ayah,
        onReciteFrom: () {
          Navigator.pop(context);
          _c.restartFrom(ayah);
          _scrollToAyah(ayah);
        },
        onListen: () {
          Navigator.pop(context);
          _playFromAyah(ayah);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: Listenable.merge([_c, settings, AppScope.of(context).subscription]),
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('سورة ${widget.surah.name}'),
            actions: [
              IconButton(
                tooltip: _c.hidden ? 'إظهار النص' : 'وضع الحفظ (إخفاء النص)',
                icon: Icon(_c.hidden ? Icons.visibility_off : Icons.visibility_outlined),
                onPressed: _c.toggleHidden,
              ),
              IconButton(
                tooltip: _playingAyah == null ? 'استمع' : 'إيقاف الاستماع',
                icon: Icon(_playingAyah == null ? Icons.headphones_outlined : Icons.stop_circle_outlined),
                onPressed: () => _playingAyah == null ? _playFromAyah(_c.currentAyah) : _stopAudio(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                // Built lazily: long surahs (al-Baqarah has 6,000+ words)
                // stay smooth on older phones.
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: widget.surah.ayahCount + 1,
                  itemBuilder: (context, i) =>
                      i == 0 ? _SurahHeader(surah: widget.surah) : _buildAyah(i, settings.fontSize),
                ),
              ),
              _ControlBar(controller: _c, onMic: _toggleMic),
            ],
          ),
        );
      },
    );
  }


  Widget _buildAyah(int ayah, double fontSize) {
    final settings = AppScope.of(context).settings;
    final colors = WordColors.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final position = _c.position;
    final active = (_c.isListening && _c.currentAyah == ayah) || _playingAyah == ayah;
    final tier = _c.tier;
    final showTajweed = tier.detectsTajweed && settings.tajweedColors;
    // Mistakes stay out of the text while reciting (they go to the margin),
    // unless the reader asked to see them live. Afterwards they get a quiet
    // dotted underline for review.
    final markMistakes = tier.detectsMistakes && (settings.mistakesInText || !_c.isListening);
    final spans = <InlineSpan>[];
    for (final i in _wordsByAyah[ayah - 1]) {
      final word = _c.words[i];
      final state = _c.tracker.stateOf(i);
      final hidden = _c.hidden && state.status == WordStatus.pending && !_c.peeked.contains(i);
      final isNext = _c.isListening && i == position;
      final recited = state.status != WordStatus.pending;
      final mistake = state.status.isMistake;
      final mistakeColor = colors.forStatus(state.status);

      Color? base = recited ? colors.correct : scheme.onSurface;
      if (state.tentative) base = base.withValues(alpha: 0.7);
      if (mistake && markMistakes && settings.mistakesInText) base = mistakeColor;
      final Color? background = hidden ? scheme.surfaceContainerHighest : (isNext ? colors.current : null);
      final style = TextStyle(
        color: hidden ? scheme.surfaceContainerHighest : base,
        backgroundColor: background,
        decoration: mistake && markMistakes ? TextDecoration.underline : null,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: mistakeColor,
      );
      if (showTajweed && !hidden && word.tajweed.isNotEmpty) {
        spans.add(TextSpan(style: style, children: _tajweedSpans(word, theme.brightness)));
      } else {
        spans.add(TextSpan(text: word.text, style: style));
      }
      spans.add(const TextSpan(text: ' '));
    }
    spans.add(TextSpan(
      text: '﴿${arabicNumber(ayah)}﴾ ',
      style: TextStyle(color: scheme.primary, fontSize: fontSize * 0.8),
    ));
    final notes = _c.marginNotes(ayah);
    return Row(
      key: _ayahKeys[ayah],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showAyahSheet(ayah),
            onLongPress: _c.hidden
                ? () {
                    for (final i in _wordsByAyah[ayah - 1]) {
                      _c.peek(i);
                    }
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: active ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text.rich(
                TextSpan(children: spans),
                textAlign: TextAlign.justify,
                textDirection: TextDirection.rtl,
                style: TextStyle(fontFamily: 'AmiriQuran', fontSize: fontSize, height: 2.1),
              ),
            ),
          ),
        ),
        // The margin: a quiet note count, opened by tapping.
        SizedBox(
          width: 30,
          child: notes.isEmpty
              ? null
              : Padding(
                  padding: EdgeInsets.only(top: fontSize * 0.6),
                  child: MarginMarker(notes: notes, onTap: () => _showAyahSheet(ayah)),
                ),
        ),
      ],
    );
  }

  /// A word split into spans colored by tajweed rule.
  List<InlineSpan> _tajweedSpans(QuranWord word, Brightness brightness) {
    final marks = [...word.tajweed]..sort((a, b) => a.start.compareTo(b.start));
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in marks) {
      if (m.start < at) continue;
      if (m.start > at) out.add(TextSpan(text: word.text.substring(at, m.start)));
      out.add(TextSpan(
        text: word.text.substring(m.start, m.end),
        style: TextStyle(color: tajweedColor(m.rule, brightness)),
      ));
      at = m.end;
    }
    if (at < word.text.length) out.add(TextSpan(text: word.text.substring(at)));
    return out;
  }
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.surah});

  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.primary.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text('سُورَةُ ${surah.name}',
              style: TextStyle(fontFamily: 'AmiriQuran', fontSize: 24, color: scheme.primary)),
        ),
        if (surah.hasSeparateBasmala)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
                textAlign: TextAlign.center, style: TextStyle(fontFamily: 'AmiriQuran', fontSize: 24)),
          ),
      ],
    );
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.controller, required this.onMic});

  final ReciteController controller;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final colors = WordColors.of(context);
    final stats = c.tracker.statsFor();
    final String status = switch (c.status) {
      ReciteStatus.idle => c.error ?? (stats.recited == 0 ? 'اضغط على الميكروفون وابدأ التلاوة' : 'اضغط للمتابعة'),
      ReciteStatus.starting => switch (c.modelProgress) {
          null => 'جارٍ التحضير…',
          < 0 => 'جارٍ تنزيل نموذج التعرّف (مرة واحدة فقط)…',
          final p => 'جارٍ تنزيل نموذج التعرّف (مرة واحدة فقط)… ${arabicNumber((p * 100).round())}٪',
        },
      ReciteStatus.listening => 'أستمع إليك…',
      ReciteStatus.stopping => 'جارٍ إنهاء الجلسة…',
    };
    final heard = c.lastTranscript.split(' ');
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.isListening && c.lastTranscript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    heard.skip(heard.length > 8 ? heard.length - 8 : 0).join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.outline, fontSize: 14),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(status,
                            style: TextStyle(
                                fontSize: 15, color: c.error != null && c.status == ReciteStatus.idle ? scheme.error : null)),
                        // Only progress is shown while reciting; mistake counts
                        // wait until the reader stops.
                        if (stats.recited > 0)
                          Wrap(spacing: 10, children: [
                            _Stat(icon: Icons.check_circle, color: colors.correct, value: stats.recited),
                            if (!c.isListening && c.tier.detectsMistakes && stats.mistakes > 0)
                              _Stat(icon: Icons.sticky_note_2_outlined, color: colors.skipped, value: stats.mistakes),
                          ]),
                      ],
                    ),
                  ),
                  if (c.hidden)
                    IconButton.filledTonal(
                      tooltip: 'تلميح: أظهر الكلمة التالية',
                      icon: const Icon(Icons.lightbulb_outline),
                      onPressed: c.hint,
                    ),
                  const SizedBox(width: 8),
                  _MicButton(controller: c, onPressed: onMic),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.color, required this.value});

  final IconData icon;
  final Color color;
  final int value;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 3),
        Text(arabicNumber(value)),
      ]);
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.controller, required this.onPressed});

  final ReciteController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = controller.isListening;
    final busy = controller.status == ReciteStatus.starting || controller.status == ReciteStatus.stopping;
    return Stack(
      alignment: Alignment.center,
      children: [
        ValueListenableBuilder<double>(
          valueListenable: controller.level,
          builder: (context, level, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 64 + (listening ? level * 22 : 0),
            height: 64 + (listening ? level * 22 : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: listening ? 0.18 : 0),
            ),
          ),
        ),
        SizedBox(
          width: 60,
          height: 60,
          child: FloatingActionButton(
            heroTag: null,
            elevation: 0,
            shape: const CircleBorder(),
            backgroundColor: listening ? scheme.error : scheme.primary,
            foregroundColor: listening ? scheme.onError : scheme.onPrimary,
            onPressed: busy ? null : onPressed,
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.onPrimary),
                  )
                : Icon(listening ? Icons.stop_rounded : Icons.mic, size: 30),
          ),
        ),
      ],
    );
  }
}

