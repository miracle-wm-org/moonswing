import 'dart:async';

/// Paces cursor-only buffers to the stream's frame rate.
///
/// The compositor sends a `position` for every pointer motion — a gaming mouse
/// is a thousand a second — and each would otherwise cost a PipeWire buffer.
/// So a change is sent at once if the last buffer went out at least
/// [minInterval] ago, and otherwise once that interval is up, carrying
/// whatever the cursor is by then: the *last* position always arrives, which
/// is the one a consumer would draw. A frame going out carries the cursor too
/// ([sent]), and resets the clock.
///
/// [push] answers whether the update is settled — delivered, or nowhere to
/// deliver it. False (the consumer had no free buffer) tries again an
/// interval later, so a cursor that has stopped moving is not left drawn
/// where it was a moment before.
class CursorPacer {
  /// [now] is a monotonic reading — the default is a stopwatch started here;
  /// tests hand in the fake clock's.
  CursorPacer({
    required this.minInterval,
    required this.push,
    Duration Function()? now,
  }) : _now = now ?? _stopwatch();

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  final Duration minInterval;
  final bool Function() push;
  final Duration Function() _now;

  /// When the last buffer carrying the cursor went out; null before the first.
  Duration? _lastSent;
  Timer? _timer;
  bool _disposed = false;

  /// The cursor changed.
  void changed() {
    if (_disposed || _timer != null) return; // already owed; it reads late
    final last = _lastSent;
    final wait = last == null ? null : minInterval - (_now() - last);
    if (wait == null || wait <= Duration.zero) {
      _send();
    } else {
      _timer = Timer(wait, _send);
    }
  }

  /// A frame carrying the cursor just went out.
  void sent() {
    _timer?.cancel();
    _timer = null;
    _lastSent = _now();
  }

  void _send() {
    _timer = null;
    if (_disposed) return;
    if (push()) {
      sent();
    } else {
      _timer = Timer(minInterval, _send);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
