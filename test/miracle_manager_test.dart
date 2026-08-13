import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/miracle_manager.dart';

void main() {
  group('MiracleManager without MIRACLESOCK', () {
    test('reports Miracle as unavailable rather than as a failure', () async {
      final manager = MiracleManager(socketPath: '');

      expect(manager.unavailable, isTrue);

      await manager.connect();

      // The distinction the workspaces module renders from: nothing failed, so
      // there is no error to show and no retry to offer — the module simply
      // takes no space.
      expect(manager.connection, isNull);
      expect(manager.connecting, isFalse);
      expect(manager.lastError, isNull);
    });

    test('connect neither throws nor notifies', () async {
      final manager = MiracleManager(socketPath: '');
      var notifies = 0;
      manager.addListener(() => notifies++);

      await expectLater(manager.connect(), completes);

      // A no-op that cannot succeed must not churn every panel on every
      // monitor — nor flip `connecting` on and back off, which would flash the
      // spinner the module deliberately skips.
      expect(notifies, 0);
    });

    test('repeated connects stay a no-op', () async {
      final manager = MiracleManager(socketPath: '');

      await manager.connect();
      await manager.connect();

      expect(manager.unavailable, isTrue);
      expect(manager.lastError, isNull);
    });
  });

  group('MiracleManager with a socket path', () {
    test('is not unavailable, and a dead socket is a retryable failure',
        () async {
      final manager =
          MiracleManager(socketPath: '/nonexistent/graceful-shell-test.sock');

      expect(manager.unavailable, isFalse);

      await manager.connect();

      // Connecting failed, so this *is* the error state: the module offers a
      // retry, and the tooltip has something to say.
      expect(manager.connection, isNull);
      expect(manager.connecting, isFalse);
      expect(manager.lastError, isNotNull);
      // _describe strips the address/errno tail SocketException.toString() adds.
      expect(manager.lastError, isNot(contains('address =')));
    });

    test('a failed attempt leaves the manager retryable', () async {
      final manager =
          MiracleManager(socketPath: '/nonexistent/graceful-shell-test.sock');

      await manager.connect();
      final first = manager.lastError;
      await manager.connect();

      // The connecting/connected guard must not latch: a second attempt has to
      // reach the socket again, which is what the retry button depends on.
      expect(manager.lastError, isNotNull);
      expect(manager.lastError, first);
    });
  });
}
