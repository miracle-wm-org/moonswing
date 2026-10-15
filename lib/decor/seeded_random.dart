/// The one source of randomness in `lib/decor/`: seeded, and the same on every
/// machine and every run.
///
/// Every texture and every plant here is *generated*, and the generator has to
/// answer the same way twice: the tile a bar was painted with on one monitor
/// must be the tile it is painted with on the next, a vine must not jump to a
/// new shape because a theme colour moved, and a test must be able to pin what
/// grows. `dart:math`'s `Random(seed)` is deterministic within one SDK but its
/// sequence is not a documented contract, so this is mulberry32 — four lines,
/// with a sequence that is.
library;

import 'dart:math' as math;

/// A small, fast, seeded generator (mulberry32).
class SeededRandom {
  SeededRandom(int seed) : _state = seed & 0xFFFFFFFF;

  int _state;

  /// The next 32 bits.
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >>> 14)) & 0xFFFFFFFF;
  }

  /// A double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;

  /// A double in `[lo, hi)`.
  double range(double lo, double hi) => lo + (hi - lo) * nextDouble();

  /// An int in `[0, n)`.
  int nextInt(int n) => n <= 0 ? 0 : nextUint32() % n;

  /// True with probability [p].
  bool chance(double p) => nextDouble() < p;

  /// A roughly normal value around 0 with deviation about [spread]: the mean of
  /// three uniforms, which is all the bell a leaf's jitter needs.
  double jitter(double spread) =>
      (nextDouble() + nextDouble() + nextDouble() - 1.5) * spread * 1.15;

  /// 32-bit multiply, as JavaScript's `Math.imul` — what mulberry32 is written
  /// against, and what Dart's 64-bit ints have to be masked down to.
  static int _imul(int a, int b) {
    final lo = (a & 0xFFFF) * b;
    final hi = (((a >>> 16) & 0xFFFF) * b) & 0xFFFF;
    return (lo + (hi << 16)) & 0xFFFFFFFF;
  }
}

/// Mixes values into one seed, so a seed can be derived from what a picture
/// depends on (a material, a tint, a length) without two inputs colliding.
int mixSeed(Iterable<int> parts) {
  var h = 0x811C9DC5;
  for (final p in parts) {
    h ^= p & 0xFFFFFFFF;
    h = (h * 0x01000193) & 0xFFFFFFFF;
    h ^= h >>> 13;
  }
  return h;
}

/// Smooth periodic value noise on a 1-D lattice of [period] cells: what bends a
/// grain line or a ridge so it wanders without ever kinking, and joins itself
/// at the tile's edge so the tile repeats without a seam.
class PeriodicNoise1D {
  PeriodicNoise1D(int seed, this.period)
      : _values = List<double>.generate(
            period, (_) => 0, growable: false) {
    final rng = SeededRandom(seed);
    for (var i = 0; i < period; i++) {
      _values[i] = rng.range(-1, 1);
    }
  }

  final int period;
  final List<double> _values;

  /// Noise at [x], where one lattice cell is 1 unit; periodic in [period].
  double at(double x) {
    final i = x.floor();
    final f = x - i;
    final a = _values[i % period];
    final b = _values[(i + 1) % period];
    final s = f * f * (3 - 2 * f);
    return a + (b - a) * s;
  }

  /// Two octaves of [at], for a line that wanders on two scales at once.
  double fbm(double x) => at(x) * 0.7 + at(x * 2 + 17.3) * 0.3;
}

/// Clamps [v] into `[0, 1]`.
double unit(double v) => math.max(0.0, math.min(1.0, v));
