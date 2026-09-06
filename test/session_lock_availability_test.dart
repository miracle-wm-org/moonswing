import 'package:ext_session_lock/ext_session_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Deliberately does not assert *which* answer comes back: that depends on
  // whether libgtk-session-lock0 happens to be installed on the machine running
  // the tests. What must hold either way is that asking never throws — the shell
  // has to start on a box without the library, with only locking unavailable.
  //
  // Note this only exercises `isAvailable` (a dlopen plus symbol lookups).
  // `isSupported` calls into GTK, which has no display here.
  test('probing for session-lock support never throws', () {
    expect(SessionLock.isAvailable, isA<bool>());
  });

  test('probing repeatedly is stable and cached', () {
    final first = SessionLock.isAvailable;
    expect(SessionLock.isAvailable, first);
    expect(SessionLock.isAvailable, first);
  });
}
