import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// Pumps the field the way the settings pane does: under a ThemeScope, with a
/// root Overlay for the picker to float into.
///
/// [respell] stands in for the trip a value takes through the theme store and
/// back — the pane never feeds the field's own string back, it feeds
/// `ThemeConfig.formatColor` of the parsed colour. That round trip is what used
/// to close the picker on the first drag.
///
/// Returns the notifier driving `initial`. An Overlay reads `initialEntries` only
/// on its first build, so a test that changes the colour has to push it through
/// here rather than through a second `pumpWidget`.
Future<ValueNotifier<String>> pumpField(
  WidgetTester tester, {
  required String initial,
  ValueChanged<String>? onChanged,
  String Function(String)? respell,
  bool locked = false,
  VoidCallback? onLockedTap,
}) async {
  final value = ValueNotifier<String>(initial);
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
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: ValueListenableBuilder<String>(
                    valueListenable: value,
                    builder: (_, v, _) => SettingsColorField(
                      initial: v,
                      locked: locked,
                      onLockedTap: onLockedTap,
                      onChanged: (hex) {
                        onChanged?.call(hex);
                        if (respell != null) value.value = respell(hex);
                      },
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
  return value;
}

/// What the settings pane actually feeds back: the colour re-serialized by the
/// theme config, whose spelling is its own business.
String _roundTrip(String hex) =>
    ThemeConfig.formatColor(parseHexColor(hex)!);

/// The swatch is the first [CompositedTransformTarget] in the field —
/// EditableText plants one of its own for the selection toolbar.
Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(find.byType(CompositedTransformTarget).first);
  await tester.pumpAndSettle();
}

bool _open() => find.byType(SettingsColorPicker).evaluate().isNotEmpty;

/// The colour the swatch is drawing. Its `Container` is the only one under the
/// swatch's [CompositedTransformTarget].
Color? swatchColor(WidgetTester tester) {
  final box = tester.widget<Container>(
    find.descendant(
      of: find.byType(CompositedTransformTarget).first,
      matching: find.byType(Container),
    ),
  );
  return (box.decoration as BoxDecoration).color;
}

/// What the row's hex field is showing. The picker's own entry is inserted into
/// the overlay after it, so `.first` is the row's either way.
String fieldText(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText).first)
    .controller
    .text;

Future<void> typeHex(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(EditableText).first, text);
  await tester.pump();
}

/// The card is 224 wide with 12px of padding; the saturation/value square is
/// the 200x150 region inside it.
Rect _card(WidgetTester tester) => tester.getRect(find.byType(SettingsColorPicker));

void main() {
  testWidgets('opens on the swatch, and tapping it again dismisses',
      (tester) async {
    await pumpField(tester, initial: '#FF5733');
    expect(_open(), isFalse);

    final swatch = tester.getCenter(find.byType(CompositedTransformTarget).first);
    await openPicker(tester);
    expect(_open(), isTrue);

    // The barrier covers the swatch while the picker is up, so the second tap
    // dismisses as an outside click rather than reaching _toggle. Either way
    // the user gets the picker closed.
    await tester.tapAt(swatch);
    await tester.pumpAndSettle();
    expect(_open(), isFalse);
  });

  testWidgets('dragging the square keeps the picker open and reports changes',
      (tester) async {
    final picked = <String>[];
    await pumpField(
      tester,
      initial: '#FF5733',
      onChanged: picked.add,
      respell: _roundTrip,
    );
    await openPicker(tester);

    final square = _card(tester).topLeft + const Offset(60, 60);
    final gesture = await tester.startGesture(square);
    await tester.pump();
    await gesture.moveBy(const Offset(30, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(picked, isNotEmpty);
    expect(_open(), isTrue, reason: 'a drag inside the picker must not dismiss');
  });

  testWidgets('a lowercase respelling of our own value does not close it',
      (tester) async {
    // The regression in miniature: the field wrote one spelling and got another
    // back, and read that as somebody else re-seeding it.
    await pumpField(
      tester,
      initial: '#FF5733',
      respell: (hex) => hex.toLowerCase(),
    );
    await openPicker(tester);

    await tester.tapAt(_card(tester).topLeft + const Offset(60, 60));
    await tester.pumpAndSettle();

    expect(_open(), isTrue);
  });

  testWidgets('clicking the card padding does not dismiss', (tester) async {
    await pumpField(tester, initial: '#FF5733', respell: _roundTrip);
    await openPicker(tester);

    // Inside the card, inside the 12px padding, clear of every control.
    await tester.tapAt(_card(tester).topLeft + const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(_open(), isTrue);
  });

  testWidgets('tapping outside dismisses', (tester) async {
    await pumpField(tester, initial: '#FF5733', respell: _roundTrip);
    await openPicker(tester);

    await tester.tapAt(
      tester.getSize(find.byType(Overlay).first).bottomRight(
            const Offset(-5, -5),
          ),
    );
    await tester.pumpAndSettle();

    expect(_open(), isFalse);
  });

  testWidgets('a theme switch closes an open picker', (tester) async {
    final value = await pumpField(tester, initial: '#FF5733');
    await openPicker(tester);
    expect(_open(), isTrue);

    // A genuinely different colour arriving from underneath.
    value.value = '#3355FF';
    await tester.pump();
    // OverlayEntry.remove() from didUpdateWidget lands after the frame.
    await tester.pump();

    expect(_open(), isFalse);
  });

  testWidgets('locked routes the tap to onLockedTap and opens nothing',
      (tester) async {
    var duplicated = 0;
    await pumpField(
      tester,
      initial: '#FF5733',
      locked: true,
      onLockedTap: () => duplicated++,
    );

    // tapAt rather than tap: the whole locked row is behind an IgnorePointer,
    // so the swatch itself is not what receives the click any more.
    await tester.tapAt(
      tester.getCenter(find.byType(CompositedTransformTarget).first),
    );
    await tester.pumpAndSettle();

    expect(duplicated, 1);
    expect(_open(), isFalse);
  });

  testWidgets('a hex typed into the row is reported as it is typed',
      (tester) async {
    final picked = <String>[];
    await pumpField(
      tester,
      initial: '#FF5733',
      onChanged: picked.add,
      respell: _roundTrip,
    );

    await typeHex(tester, '#3355FF');

    expect(picked, ['#3355FF']);
    expect(swatchColor(tester), const Color(0xFF3355FF));
    expect(_open(), isFalse, reason: 'typing must not need the picker');
  });

  testWidgets('the # is optional, and eight digits set the alpha',
      (tester) async {
    final picked = <String>[];
    await pumpField(
      tester,
      initial: '#FF5733',
      onChanged: picked.add,
      respell: _roundTrip,
    );

    await typeHex(tester, 'aabbcc');
    expect(picked, ['#AABBCC']);

    await typeHex(tester, '#80AABBCC');
    expect(picked.last, '#80AABBCC');
    expect(swatchColor(tester), const Color(0x80AABBCC));
  });

  testWidgets('a half-typed hex reports nothing and the swatch holds',
      (tester) async {
    // Every hex is half-typed on its way in, so a parse failure here is the
    // ordinary case: nothing is reported, and the swatch goes on drawing the
    // colour the config still holds rather than blinking to its `?`.
    final picked = <String>[];
    await pumpField(
      tester,
      initial: '#FF5733',
      onChanged: picked.add,
      respell: _roundTrip,
    );

    await typeHex(tester, '#33');
    expect(picked, isEmpty);
    expect(swatchColor(tester), const Color(0xFFFF5733));

    await typeHex(tester, '#3355F');
    expect(picked, isEmpty);
    expect(swatchColor(tester), const Color(0xFFFF5733));
  });

  testWidgets('an abandoned edit settles back to the value the config holds',
      (tester) async {
    await pumpField(tester, initial: '#FF5733', respell: _roundTrip);

    await typeHex(tester, '#33');
    expect(fieldText(tester), '#33');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fieldText(tester), '#FF5733');
  });

  testWidgets('a finished edit settles to the canonical spelling',
      (tester) async {
    await pumpField(tester, initial: '#FF5733', respell: _roundTrip);

    await typeHex(tester, 'aabbcc');
    expect(fieldText(tester), 'aabbcc', reason: 'never rewritten mid-typing');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fieldText(tester), '#AABBCC');
  });

  testWidgets('focusing the field closes an open picker', (tester) async {
    // Two editors for one colour, and the picker snapshots its HSV at open.
    await pumpField(tester, initial: '#FF5733', respell: _roundTrip);
    await openPicker(tester);
    expect(_open(), isTrue);

    await tester.showKeyboard(find.byType(EditableText).first);
    await tester.pumpAndSettle();

    expect(_open(), isFalse);
  });

  testWidgets('a locked field takes no typing either', (tester) async {
    var duplicated = 0;
    await pumpField(
      tester,
      initial: '#FF5733',
      locked: true,
      onLockedTap: () => duplicated++,
    );

    await tester.tapAt(tester.getCenter(find.byType(SettingsTextField)));
    await tester.pumpAndSettle();

    expect(duplicated, 1, reason: 'the click offers to duplicate the theme');
    expect(fieldText(tester), '#FF5733');
  });

  test('formatHexColor spells hex the way the theme config does', () {
    expect(formatHexColor(const Color(0xFFFF5733)), '#FF5733');
    expect(formatHexColor(const Color(0x80AABBCC)), '#80AABBCC');
    for (final c in [const Color(0xFFFF5733), const Color(0x80AABBCC)]) {
      expect(formatHexColor(c), ThemeConfig.formatColor(c));
    }
  });
}
