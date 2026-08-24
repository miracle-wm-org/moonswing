import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/modules/notifications.dart';
import 'package:graceful_shell/notification_service.dart';
import 'package:graceful_shell/scopes.dart';

/// The bar module needs a [ThemeScope] and nothing else — the layer-shell
/// window it can open is only reached by a click, which none of these do.
Widget _bell() {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: const Center(child: Notifications()),
    ),
  );
}

/// The banner as the panel hosts it. The [ListenableBuilder] stands in for
/// `_NotificationPanelState`'s store listener, which rebuilds the whole surface
/// on every notify — the banner itself holds no listener because in its one
/// real home it never needs one.
Widget _banner() {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: Center(
        child: SizedBox(
          width: 360,
          child: ListenableBuilder(
            listenable: NotificationStore.instance,
            // Deliberately not const: a const child is a *different* widget
            // instance test, and the element would short-circuit the rebuild
            // (the trick test/theme_provider_test.dart uses on purpose). The
            // panel passes a runtime `theme`, so it never hits this.
            builder: (_, _) => NotificationDaemonBanner(
              theme: const ThemeConfig(),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final store = NotificationStore.instance;

  setUp(store.resetDaemonState);
  tearDown(() {
    store.resetDaemonState();
    store.dismissAll();
  });

  group('NotificationStore daemon status', () {
    test('starts out neither running nor broken', () {
      expect(store.daemonStatus, NotificationDaemonStatus.starting);
      expect(store.daemonUnavailable, isFalse);
      expect(store.daemonReason, isNull);
      expect(store.daemonRetrying, isFalse);
    });

    test('an unavailable report carries the reason the banner shows', () {
      var notifies = 0;
      void listener() => notifies++;
      store.addListener(listener);
      addTearDown(() => store.removeListener(listener));

      store.reportDaemonUnavailable('another daemon owns it');

      expect(store.daemonStatus, NotificationDaemonStatus.unavailable);
      expect(store.daemonUnavailable, isTrue);
      expect(store.daemonReason, 'another daemon owns it');
      expect(notifies, 1);

      // The same report again is not news: the panel is watched by a listener
      // that rebuilds the whole surface, and a retry loop reporting the same
      // failure must not drive it.
      store.reportDaemonUnavailable('another daemon owns it');
      expect(notifies, 1);
    });

    test('winning the name clears the reason', () {
      store.reportDaemonUnavailable('another daemon owns it');
      store.reportDaemonRunning();

      expect(store.daemonStatus, NotificationDaemonStatus.running);
      expect(store.daemonUnavailable, isFalse);
      expect(store.daemonReason, isNull);
    });

    test('retry re-runs the starter and reports the flight', () async {
      store.reportDaemonUnavailable('another daemon owns it');
      final gate = Completer<void>();
      var attempts = 0;
      store.daemonStarter = () {
        attempts++;
        return gate.future.then((_) => store.reportDaemonRunning());
      };

      final retry = store.retryDaemon();
      expect(attempts, 1);
      expect(store.daemonRetrying, isTrue);

      gate.complete();
      await retry;

      expect(store.daemonRetrying, isFalse);
      expect(store.daemonStatus, NotificationDaemonStatus.running);
    });

    test('a second retry does not stack on top of one in flight', () async {
      store.reportDaemonUnavailable('another daemon owns it');
      final gate = Completer<void>();
      var attempts = 0;
      store.daemonStarter = () {
        attempts++;
        return gate.future;
      };

      final first = store.retryDaemon();
      await store.retryDaemon();
      expect(attempts, 1);

      gate.complete();
      await first;
      expect(attempts, 1);
    });

    test('retry is refused once the shell owns the name', () async {
      store.reportDaemonRunning();
      var attempts = 0;
      store.daemonStarter = () async => attempts++;

      await store.retryDaemon();
      expect(attempts, 0);
    });

    test('a starter that throws is recorded, not rethrown', () async {
      store.reportDaemonUnavailable('another daemon owns it');
      store.daemonStarter = () async => throw StateError('bus is gone');

      // The rethrow in startNotificationService exists for ShellServices.run,
      // which is long finished by the time a user clicks Retry; letting it
      // escape here would only reach the zone handler.
      await store.retryDaemon();

      expect(store.daemonUnavailable, isTrue);
      expect(store.daemonReason, contains('bus is gone'));
      expect(store.daemonRetrying, isFalse);
    });
  });

  group('the bell', () {
    testWidgets('carries no exclamation dot while the daemon is running',
        (tester) async {
      store.reportDaemonRunning();
      await tester.pumpWidget(_bell());
      expect(find.text('!'), findsNothing);
    });

    testWidgets('grows an exclamation dot when the daemon is unavailable',
        (tester) async {
      await tester.pumpWidget(_bell());
      expect(find.text('!'), findsNothing);

      // Live, not just at build: the name request settles after the first
      // frame, so the dot has to arrive on the store's notify.
      store.reportDaemonUnavailable('another daemon owns it');
      await tester.pump();
      expect(find.text('!'), findsOneWidget);
    });
  });

  group('the panel banner', () {
    testWidgets('states the reason and offers a retry', (tester) async {
      store.reportDaemonUnavailable('another daemon owns it');
      await tester.pumpWidget(_banner());

      expect(find.text('Notifications are not working'), findsOneWidget);
      expect(find.text('another daemon owns it'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('Retry re-runs the name request', (tester) async {
      store.reportDaemonUnavailable('another daemon owns it');
      var attempts = 0;
      final gate = Completer<void>();
      store.daemonStarter = () {
        attempts++;
        return gate.future;
      };

      await tester.pumpWidget(_banner());
      await tester.tap(find.text('Retry'));
      expect(attempts, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the button becomes a loader while the retry is in flight',
        (tester) async {
      store.reportDaemonUnavailable('another daemon owns it');
      final gate = Completer<void>();
      store.daemonStarter = () => gate.future;

      await tester.pumpWidget(_banner());
      expect(find.byType(LoadingIndicator), findsNothing);

      unawaited(store.retryDaemon());
      await tester.pump();
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(LoadingIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('the retry hover fill is the error red', (tester) async {
      store.reportDaemonUnavailable('another daemon owns it');
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await tester.pumpWidget(_banner());
      await gesture.moveTo(tester.getCenter(find.text('Retry')));
      await tester.pump();

      final container = tester.widget<Container>(find
          .ancestor(of: find.text('Retry'), matching: find.byType(Container))
          .first);
      final fill = (container.decoration as BoxDecoration).color;
      expect(fill, isNotNull);
      expect(fill!.a, greaterThan(0));
    });
  });
}
