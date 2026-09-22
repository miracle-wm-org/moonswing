import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

/// The destructive-action confirmation the settings panes open — currently the
/// panel remove button in `Panels & Layout`.
///
/// Driven through [showSettingsConfirm] rather than the settings page, which
/// reads `ConfigStore.instance` and so cannot be pumped without the real
/// `config.toml` behind it.

/// Pumps a button that opens the confirmation into a root [Overlay], the way
/// the settings pane hosts it. Returns the answers as they resolve.
Future<List<bool>> pumpConfirm(
  WidgetTester tester, {
  String? warning,
}) async {
  final answers = <bool>[];
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Align(
                  alignment: Alignment.topLeft,
                  child: GestureDetector(
                    onTap: () async {
                      answers.add(await showSettingsConfirm(
                        context,
                        title: 'Remove the Top panel?',
                        message: 'It is deleted from config.toml.',
                        warning: warning,
                        confirmLabel: 'Remove',
                      ));
                    },
                    child: const SizedBox(
                      width: 40,
                      height: 20,
                      child: Text('open'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return answers;
}

bool _open() => find.byType(SettingsConfirmCard).evaluate().isNotEmpty;

Future<void> _open_(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirming resolves true and takes the card down',
      (tester) async {
    final answers = await pumpConfirm(tester);
    await _open_(tester);
    expect(_open(), isTrue);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
    expect(_open(), isFalse);
  });

  testWidgets('cancelling resolves false', (tester) async {
    final answers = await pumpConfirm(tester);
    await _open_(tester);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [false]);
    expect(_open(), isFalse);
  });

  // A click outside a confirmation is a refusal, not a deferral — the same rule
  // the screencast picker follows.
  testWidgets('tapping the scrim resolves false', (tester) async {
    final answers = await pumpConfirm(tester);
    await _open_(tester);

    // Well clear of the 380-wide card centred in the 800x600 test surface.
    await tester.tapAt(const Offset(20, 560));
    await tester.pumpAndSettle();

    expect(answers, [false]);
    expect(_open(), isFalse);
  });

  testWidgets('Escape resolves false', (tester) async {
    final answers = await pumpConfirm(tester);
    await _open_(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(answers, [false]);
    expect(_open(), isFalse);
  });

  // Separate tests, not one with two pumps: an Overlay reads `initialEntries`
  // only on its first build, so a second `pumpWidget` of the same shape keeps
  // the first entry's closure.
  testWidgets('no warning paragraph when none is given', (tester) async {
    await pumpConfirm(tester);
    await _open_(tester);
    expect(find.textContaining('last panel'), findsNothing);
  });

  testWidgets('the warning paragraph shows when one is given', (tester) async {
    await pumpConfirm(tester, warning: 'This is the last panel.');
    await _open_(tester);
    expect(find.textContaining('last panel'), findsOneWidget);
  });
}
