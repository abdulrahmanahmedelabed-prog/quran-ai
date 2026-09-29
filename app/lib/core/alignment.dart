/// Word-level alignment between what the reciter said and the mushaf text.
///
/// This is the heart of mistake detection: every heard word is either matched
/// to an expected word (correctly or not), or treated as an extra word
/// (repetition, isti'adha, recognizer noise); expected words that were passed
/// over are skips. Skipping uses an affine cost so that jumping over a whole
/// ayah is one decision rather than a long chain of penalties.
library;

import 'arabic.dart';

enum AlignOpKind {
  /// A heard word (or several merged heard words) aligned to an expected word.
  match,

  /// An expected word the reciter passed over.
  skip,

  /// A heard word that does not correspond to any expected word.
  extra,
}

class AlignOp {
  const AlignOp.match(this.expected, this.heardStart, this.heardEnd, this.similarity)
      : kind = AlignOpKind.match;
  const AlignOp.skip(this.expected)
      : kind = AlignOpKind.skip,
        heardStart = -1,
        heardEnd = -1,
        similarity = 0;
  const AlignOp.extra(this.heardStart)
      : kind = AlignOpKind.extra,
        expected = -1,
        heardEnd = heardStart + 1,
        similarity = 0;

  final AlignOpKind kind;

  /// Index into the expected window, or -1 for [AlignOpKind.extra].
  final int expected;

  /// Heard word range `[heardStart, heardEnd)`, or -1 for [AlignOpKind.skip].
  final int heardStart;
  final int heardEnd;
  final double similarity;

  @override
  String toString() => switch (kind) {
        AlignOpKind.match => 'match(e$expected<-h$heardStart..$heardEnd ${similarity.toStringAsFixed(2)})',
        AlignOpKind.skip => 'skip(e$expected)',
        AlignOpKind.extra => 'extra(h$heardStart)',
      };
}

class AlignmentResult {
  const AlignmentResult(this.ops, this.cost);

  final List<AlignOp> ops;
  final double cost;

  /// Number of expected words consumed (index after the last matched word).
  int get expectedConsumed {
    for (var k = ops.length - 1; k >= 0; k--) {
      if (ops[k].kind == AlignOpKind.match) return ops[k].expected + 1;
    }
    return 0;
  }

  /// Number of heard words up to and including the last matched word.
  int get heardConsumedByMatches {
    for (var k = ops.length - 1; k >= 0; k--) {
      if (ops[k].kind == AlignOpKind.match) return ops[k].heardEnd;
    }
    return 0;
  }

  Iterable<AlignOp> get matches => ops.where((o) => o.kind == AlignOpKind.match);
}

class AlignerConfig {
  const AlignerConfig({
    this.threshold = 0.8,
    this.extraCost = 0.8,
    this.skipOpenCost = 1.0,
    this.skipExtendCost = 0.1,
    this.maxMerge = 5,
  });

  /// Minimum [wordSimilarity] for a heard word to count as correct.
  final double threshold;
  final double extraCost;
  final double skipOpenCost;
  final double skipExtendCost;

  /// How many heard words may be joined to match one expected word. Needed
  /// because Uthmani joins words imla'i separates (يَٰٓأَيُّهَا = يا أيها) and
  /// because muqatta'at are pronounced letter by letter (الٓمٓ = الف لام ميم).
  final int maxMerge;
}

const double _inf = double.infinity;

/// Similarity of [heard] against the best of an expected word's accepted forms.
double bestSimilarity(String heard, List<String> forms) {
  var best = 0.0;
  for (final f in forms) {
    final s = wordSimilarity(heard, f);
    if (s > best) best = s;
    if (best == 1) break;
  }
  return best;
}

/// Aligns [heard] words against [expected] words (each given as its list of
/// accepted normalized forms).
///
/// The alignment must account for every heard word but may stop anywhere in
/// [expected] (the reciter simply has not got further yet). With
/// [freeLeadingSkips], expected words before the first match cost nothing,
/// which turns this into a local search used for locating a passage.
AlignmentResult alignWords(
  List<List<String>> expected,
  List<String> heard, {
  AlignerConfig config = const AlignerConfig(),
  bool freeLeadingSkips = false,
}) {
  final n = expected.length;
  final m = heard.length;
  if (m == 0) return const AlignmentResult([], 0);

  // Similarity cache for single heard words.
  final sim = List.generate(m, (_) => List<double>.filled(n, -1));
  double simAt(int j, int i) {
    final v = sim[j][i];
    if (v >= 0) return v;
    return sim[j][i] = bestSimilarity(heard[j], expected[i]);
  }

  double matchCost(double s) =>
      s >= config.threshold ? (1 - s) * 0.2 : 1.1 - 0.3 * s;

  // Two states (Gotoh): mState = last op consumed a heard word (or start),
  // gState = last op was a skip. Costs indexed [j][i].
  final mCost = List.generate(m + 1, (_) => List<double>.filled(n + 1, _inf));
  final gCost = List.generate(m + 1, (_) => List<double>.filled(n + 1, _inf));
  // Back pointers for mState: op code and span.
  //   0 = start, 1 = extra, 2 = match (span = merged heard words).
  final mOp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  final mSpan = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  final mFromG = List.generate(m + 1, (_) => List<bool>.filled(n + 1, false));
  final mSim = List.generate(m + 1, (_) => List<double>.filled(n + 1, 0));
  final gFromG = List.generate(m + 1, (_) => List<bool>.filled(n + 1, false));

  mCost[0][0] = 0;
  for (var i = 1; i <= n; i++) {
    if (freeLeadingSkips) {
      // Treat as a fresh start at position i.
      mCost[0][i] = 0;
    } else {
      final open = mCost[0][i - 1] + config.skipOpenCost;
      final ext = gCost[0][i - 1] + config.skipExtendCost;
      if (ext <= open) {
        gCost[0][i] = ext;
        gFromG[0][i] = true;
      } else {
        gCost[0][i] = open;
      }
    }
  }

  for (var j = 1; j <= m; j++) {
    for (var i = 0; i <= n; i++) {
      // Extra heard word.
      var best = _inf;
      var op = 0, span = 0;
      var fromG = false;
      var bestSim = 0.0;
      final prevM = mCost[j - 1][i], prevG = gCost[j - 1][i];
      if (prevM + config.extraCost < best) {
        best = prevM + config.extraCost;
        op = 1;
        fromG = false;
      }
      if (prevG + config.extraCost < best) {
        best = prevG + config.extraCost;
        op = 1;
        fromG = true;
      }
      if (i > 0) {
        // Single-word match or substitution.
        final s = simAt(j - 1, i - 1);
        final c = matchCost(s);
        final pm = mCost[j - 1][i - 1], pg = gCost[j - 1][i - 1];
        final p = pm <= pg ? pm : pg;
        if (p + c < best) {
          best = p + c;
          op = 2;
          span = 1;
          fromG = pg < pm;
          bestSim = s;
        }
        // Several heard words joined into one expected word (matches only).
        final maxK = j < config.maxMerge ? j : config.maxMerge;
        for (var k = 2; k <= maxK; k++) {
          final joined = heard.sublist(j - k, j).join();
          final sk = bestSimilarity(joined, expected[i - 1]);
          if (sk < config.threshold) continue;
          final ck = matchCost(sk) + 0.05 * (k - 1);
          final qm = mCost[j - k][i - 1], qg = gCost[j - k][i - 1];
          final q = qm <= qg ? qm : qg;
          if (q + ck < best) {
            best = q + ck;
            op = 2;
            span = k;
            fromG = qg < qm;
            bestSim = sk;
          }
        }
      }
      mCost[j][i] = best;
      mOp[j][i] = op;
      mSpan[j][i] = span;
      mFromG[j][i] = fromG;
      mSim[j][i] = bestSim;

      // Skip state for this cell is computed after mCost[j][i-1] is final.
      if (i > 0) {
        final open = mCost[j][i - 1] + config.skipOpenCost;
        final ext = gCost[j][i - 1] + config.skipExtendCost;
        if (ext < open) {
          gCost[j][i] = ext;
          gFromG[j][i] = true;
        } else {
          gCost[j][i] = open;
          gFromG[j][i] = false;
        }
      }
    }
  }

  // Free end in expected: the reciter may stop anywhere. Ending in the skip
  // state is never better than ending before the skip, so only mState counts.
  var endI = 0;
  var endCost = _inf;
  for (var i = 0; i <= n; i++) {
    // Prefer the earliest end on ties (don't claim progress without evidence).
    if (mCost[m][i] < endCost - 1e-9) {
      endCost = mCost[m][i];
      endI = i;
    }
  }

  final ops = <AlignOp>[];
  var j = m, i = endI;
  var inG = false;
  while (j > 0 || i > 0) {
    if (inG) {
      ops.add(AlignOp.skip(i - 1));
      inG = gFromG[j][i];
      i--;
      continue;
    }
    if (j == 0) {
      if (freeLeadingSkips) break;
      // Leading skips before anything was heard.
      inG = true;
      continue;
    }
    switch (mOp[j][i]) {
      case 1:
        ops.add(AlignOp.extra(j - 1));
        inG = mFromG[j][i];
        j--;
      case 2:
        final k = mSpan[j][i];
        ops.add(AlignOp.match(i - 1, j - k, j, mSim[j][i]));
        inG = mFromG[j][i];
        j -= k;
        i--;
      default:
        // Only reachable for (0, i) with free leading skips.
        j = 0;
        i = 0;
    }
  }
  return AlignmentResult(ops.reversed.toList(growable: false), endCost);
}
