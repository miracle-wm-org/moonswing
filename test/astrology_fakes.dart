// Shared fakes for the astrology tests: an offline [HoroscopeClient].
//
// Not a `_test.dart` file, so `flutter test` does not try to run it. The point
// is `weather_fakes.dart`'s — every astrology test in the suite takes a real
// lease on a real store, and not one of them may reach for a network the test
// runner does not have.

import 'dart:async';

import 'package:graceful_shell/astrology/horoscope_api.dart';

/// A client that answers from what it was handed, records what it was asked,
/// and opens nothing.
class FakeHoroscopeClient implements HoroscopeClient {
  FakeHoroscopeClient({
    this.text = 'The stars are indifferent, but pleasantly so.',
    this.failWith,
    this.pending = false,
  });

  String text;

  /// When set, [fetch] throws it instead of answering.
  HoroscopeException? failWith;

  /// When true, [fetch] never completes.
  ///
  /// The only way a widget test can hold the store in its loading state: a
  /// widget takes a lease in `initState`, so the fetch it starts lands during
  /// the first `pump` and a seeded loading flag is gone before the frame the
  /// test is looking at.
  bool pending;

  int calls = 0;
  final List<String> signs = [];
  final List<HoroscopePeriod> periods = [];
  final List<String> bases = [];

  @override
  Future<HoroscopeReading> fetch({
    required String sign,
    required HoroscopePeriod period,
    required String apiBase,
  }) async {
    calls++;
    signs.add(sign);
    periods.add(period);
    bases.add(apiBase);
    if (pending) return Completer<HoroscopeReading>().future;
    final failure = failWith;
    if (failure != null) throw failure;
    return HoroscopeReading(
      text: text,
      period: period,
      date: 'August 26, 2026',
    );
  }
}
