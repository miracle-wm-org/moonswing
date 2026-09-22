import 'dart:async';

import 'package:moonswing/keyboard/locale1_client.dart';

/// A [Locale1Client] with no system bus behind it.
class FakeLocale1Client implements Locale1Client {
  FakeLocale1Client({
    Locale1Keyboard state = const Locale1Keyboard(
      layout: 'us',
      model: 'pc105',
      variant: '',
      options: '',
    ),
  }) : _state = state;

  Locale1Keyboard _state;
  final _controller = StreamController<Locale1Keyboard>.broadcast();

  /// Every [setKeyboard] call, in order.
  final List<Locale1Keyboard> writes = [];

  int reads = 0;

  /// Thrown by [read], once set.
  Locale1Failure? readFailure;

  /// Thrown by [setKeyboard], once set.
  Locale1Failure? writeFailure;

  /// Completed by the test, so a write can be held mid-flight.
  Completer<void>? gate;

  /// Whether [setKeyboard] applies the write to the reported state. False
  /// models a compositor that accepted the call but whose PropertiesChanged
  /// has not arrived.
  bool applyWrites = true;

  Locale1Keyboard get state => _state;

  /// Pushes a change from outside the shell — a `localectl` in a terminal.
  void push(Locale1Keyboard next) {
    _state = next;
    _controller.add(next);
  }

  @override
  Future<Locale1Keyboard> read() async {
    reads++;
    final failure = readFailure;
    if (failure != null) throw failure;
    return _state;
  }

  @override
  Stream<Locale1Keyboard> get changes => _controller.stream;

  @override
  Future<void> setKeyboard(Locale1Keyboard next, {bool convert = true}) async {
    final gate = this.gate;
    if (gate != null) await gate.future;
    writes.add(next);
    final failure = writeFailure;
    if (failure != null) throw failure;
    if (applyWrites) _state = next;
  }

  void dispose() => _controller.close();
}
