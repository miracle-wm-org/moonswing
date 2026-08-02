import 'dart:ffi' as ffi;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/launcher/app_search.dart';
import 'package:graceful_shell/launcher/launcher_overlay.dart';
import 'package:graceful_shell/scopes.dart';

/// Fake entries carry a null `GAppInfo*` — safe precisely because the launcher
/// takes its launch callbacks as parameters and never touches the pointer.
AppEntry _app(String name, {List<AppAction> actions = const []}) => AppEntry(
      id: name.toLowerCase(),
      name: name,
      iconName: '',
      categories: const [],
      actions: actions,
      appInfo: ffi.nullptr,
    );

final _apps = [
  _app('Firefox', actions: const [
    AppAction(id: 'new-private-window', name: 'New Private Window'),
    AppAction(id: 'new-window', name: 'New Window'),
  ]),
  _app('Files'),
  _app('Terminal'),
].map(SearchableApp.new).toList();

class _Harness {
  final closing = ValueNotifier(false);
  final launched = <String>[];
  final launchedActions = <String>[];
  var closedCount = 0;
}

Future<_Harness> pumpLauncher(
  WidgetTester tester, {
  List<SearchableApp>? apps,
}) async {
  final harness = _Harness();
  await tester.pumpWidget(
    ThemeScope(
      theme: const ThemeConfig(),
      child: Center(
        child: SizedBox(
          width: 900,
          height: 700,
          child: LauncherOverlay(
            closingNotifier: harness.closing,
            onClosed: () => harness.closedCount++,
            apps: apps ?? _apps,
            onLaunch: (app) => harness.launched.add(app.name),
            onLaunchAction: (app, action) =>
                harness.launchedActions.add('${app.name}/${action.id}'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText), text);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every application before anything is typed',
      (tester) async {
    await pumpLauncher(tester);

    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Terminal'), findsOneWidget);
  });

  testWidgets('typing filters the list', (tester) async {
    await pumpLauncher(tester);
    await _type(tester, 'fire');

    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Terminal'), findsNothing);
  });

  testWidgets('a query with no matches says so', (tester) async {
    await pumpLauncher(tester);
    await _type(tester, 'zzzz');

    expect(find.text('No matching applications'), findsOneWidget);
  });

  testWidgets('Enter launches the selected app and releases the window',
      (tester) async {
    final harness = await pumpLauncher(tester);
    await _press(tester, LogicalKeyboardKey.enter);

    expect(harness.launched, ['Firefox']);
    // Launching skips the fade-out so the new window wins the focus race.
    expect(harness.closedCount, 1);
  });

  testWidgets('Down and Up move the selection', (tester) async {
    final harness = await pumpLauncher(tester);

    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.enter);

    expect(harness.launched, ['Files']);
  });

  testWidgets('the selection cannot run off either end', (tester) async {
    final harness = await pumpLauncher(tester);

    await _press(tester, LogicalKeyboardKey.arrowUp);
    await _press(tester, LogicalKeyboardKey.enter);
    expect(harness.launched, ['Firefox']);

    for (var i = 0; i < 10; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
    }
    await _press(tester, LogicalKeyboardKey.enter);
    expect(harness.launched.last, 'Terminal');
  });

  testWidgets('clicking a row launches it', (tester) async {
    final harness = await pumpLauncher(tester);
    await tester.tap(find.text('Terminal'));
    await tester.pumpAndSettle();

    expect(harness.launched, ['Terminal']);
  });

  testWidgets('Escape asks the host to close, and closes after the fade',
      (tester) async {
    final harness = await pumpLauncher(tester);
    await _press(tester, LogicalKeyboardKey.escape);

    expect(harness.closing.value, isTrue);
    expect(harness.closedCount, 1);
  });

  testWidgets('clicking the backdrop dismisses', (tester) async {
    // Required, not polish: the surface swallows every click on the monitor,
    // including on the bar button that opened it.
    final harness = await pumpLauncher(tester);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(harness.closing.value, isTrue);
  });

  testWidgets('clicking inside the card does not dismiss it', (tester) async {
    final harness = await pumpLauncher(tester);
    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();

    expect(harness.closing.value, isFalse);
  });

  group('calculator', () {
    testWidgets('a mathematical query shows a result row', (tester) async {
      await pumpLauncher(tester);
      await _type(tester, '2^10/4');

      expect(find.text('256'), findsOneWidget);
      expect(find.text('2^10/4 ='), findsOneWidget);
    });

    testWidgets('an ordinary app query shows no result row', (tester) async {
      await pumpLauncher(tester);
      await _type(tester, 'fire');

      expect(find.textContaining('='), findsNothing);
    });
  });

  group('action flyout', () {
    testWidgets('Right at the end of the query opens it', (tester) async {
      await pumpLauncher(tester);
      await _type(tester, 'fire');
      await _press(tester, LogicalKeyboardKey.arrowRight);

      expect(find.text('New Private Window'), findsOneWidget);
      expect(find.text('New Window'), findsOneWidget);
    });

    testWidgets('Right mid-query moves the caret instead', (tester) async {
      // The search field is focused; stealing Right unconditionally would make
      // the caret unmovable.
      await pumpLauncher(tester);
      await _type(tester, 'fire');
      tester.widget<EditableText>(find.byType(EditableText)).controller
          .selection = const TextSelection.collapsed(offset: 1);
      await tester.pumpAndSettle();

      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('New Private Window'), findsNothing);
    });

    testWidgets('an app with no actions has nothing to open', (tester) async {
      await pumpLauncher(tester);
      await _type(tester, 'terminal');
      await _press(tester, LogicalKeyboardKey.arrowRight);

      expect(find.text('New Private Window'), findsNothing);
    });

    testWidgets('choosing an action launches it and closes the launcher',
        (tester) async {
      final harness = await pumpLauncher(tester);
      await _type(tester, 'fire');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.tap(find.text('New Private Window'));
      await tester.pumpAndSettle();

      expect(harness.launchedActions, ['Firefox/new-private-window']);
      expect(harness.launched, isEmpty);
      expect(harness.closedCount, 1);
    });

    testWidgets('Escape closes the flyout before it closes the launcher',
        (tester) async {
      final harness = await pumpLauncher(tester);
      await _type(tester, 'fire');
      await _press(tester, LogicalKeyboardKey.arrowRight);

      await _press(tester, LogicalKeyboardKey.escape);
      expect(find.text('New Private Window'), findsNothing);
      expect(harness.closing.value, isFalse);

      await _press(tester, LogicalKeyboardKey.escape);
      expect(harness.closing.value, isTrue);
    });
  });
}
