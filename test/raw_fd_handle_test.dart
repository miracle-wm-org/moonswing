import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/native/libc.dart';
import 'package:moonswing/native/raw_fd_handle.dart';

/// `adoptRawFd` is how `ConnectToEIS` hands libeis's socket to `package:dbus`;
/// what matters is that the descriptor survives under a number `dart:io` owns,
/// and that the scratch file it borrowed is gone.

List<String> _fdTargets() => [
      for (final entry in Directory('/proc/self/fd').listSync(followLinks: false))
        (() {
          try {
            return Link(entry.path).targetSync();
          } catch (_) {
            return '';
          }
        })(),
    ];

void main() {
  test('the adopted descriptor is the original, under a new number', () {
    final fd = memfdCreate('adopt-me');
    expect(fd, greaterThanOrEqualTo(0));

    final adopted = adoptRawFd(fd);
    expect(_fdTargets().where((t) => t.contains('memfd:adopt-me')), hasLength(1),
        reason: 'the original number is closed; one copy remains');
    expect(_fdTargets().where((t) => t.contains('moonswing-fd-')), isEmpty,
        reason: 'the scratch file is not left open or on disk');

    adopted.close();
    adopted.close(); // idempotent
    expect(_fdTargets().where((t) => t.contains('memfd:adopt-me')), isEmpty);
  });
}
