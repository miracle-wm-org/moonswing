import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/shell_services.dart';

void main() {
  group('ShellServices', () {
    test('every service starts out loading', () {
      final services = ShellServices();
      for (final service in ShellService.values) {
        expect(services.isLoading(service), isTrue, reason: service.name);
        expect(services.statusOf(service), ServiceStatus.loading);
      }
    });

    test('run defers the task past the caller, then settles it ready',
        () async {
      final services = ShellServices();
      var started = false;
      var notifies = 0;
      services.addListener(() => notifies++);

      services.run(ShellService.tray, () async => started = true);

      // The whole point of the deferral: a task that does its work before its
      // first await must not hold the isolate through the frame it was
      // registered from.
      expect(started, isFalse);
      expect(services.isLoading(ShellService.tray), isTrue);

      await pumpEventQueue();
      expect(started, isTrue);
      expect(services.statusOf(ShellService.tray), ServiceStatus.ready);
      expect(notifies, 1);
    });

    test('a task that throws settles failed, records why, and does not throw',
        () async {
      final services = ShellServices();
      services.run(
        ShellService.audio,
        () async => throw StateError('no pulse server'),
      );

      await pumpEventQueue();
      expect(services.statusOf(ShellService.audio), ServiceStatus.failed);
      expect(services.isLoading(ShellService.audio), isFalse);
      expect(services.errorOf(ShellService.audio), contains('no pulse server'));
    });

    test('run is a no-op for a service already started', () async {
      final services = ShellServices();
      var runs = 0;
      Future<void> task() async => runs++;

      services.run(ShellService.miracle, task);
      services.run(ShellService.miracle, task);
      await pumpEventQueue();

      expect(runs, 1);
    });

    test('skip settles ready without running anything', () async {
      final services = ShellServices();
      services.skip(ShellService.screencast);
      expect(services.isReady(ShellService.screencast), isTrue);

      var ran = false;
      services.run(ShellService.screencast, () async => ran = true);
      await pumpEventQueue();
      expect(ran, isFalse, reason: 'a skipped service is already settled');
    });

    test('settled() hands tests a fully started world', () {
      final services = ShellServices.settled();
      for (final service in ShellService.values) {
        expect(services.isReady(service), isTrue, reason: service.name);
      }
    });
  });

  group('ShellServicesScope', () {
    testWidgets('reports not-loading when there is no scope at all',
        (tester) async {
      late bool loading;
      await tester.pumpWidget(Builder(
        builder: (context) {
          loading =
              ShellServicesScope.isLoading(context, ShellService.applications);
          return const SizedBox();
        },
      ));

      // A module built on its own in a widget test has no main() behind it, so
      // nothing is pending and a loader would never come down.
      expect(loading, isFalse);
    });

    testWidgets('rebuilds its dependents when a service settles',
        (tester) async {
      final services = ShellServices();
      final completer = Completer<void>();
      services.run(ShellService.applications, () => completer.future);

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: ShellServicesScope(
          services: services,
          child: Builder(
            builder: (context) => Text(
              ShellServicesScope.isLoading(context, ShellService.applications)
                  ? 'loading'
                  : 'ready',
            ),
          ),
        ),
      ));
      expect(find.text('loading'), findsOneWidget);

      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('ready'), findsOneWidget);
    });
  });
}
