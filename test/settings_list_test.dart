import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/keyboard/xkb_catalog.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/keyboard/input_source_picker.dart';
import 'package:moonswing/scopes.dart';

import 'tap_target.dart';

import 'glyph_finder.dart';

/// Pins the one collection editor every settings list is built from: an
/// enclosed box of numbered rows, each with a remove icon, reordered by drag,
/// closed by the row that adds to it, and as tall as the room it is given.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double minHeight = 0,
}) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 13),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 400,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: child,
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
}

/// The string list as its own stateful host, so a test sees each emitted list
/// rendered back the way a store would render it.
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    this.suggestions,
    this.onChanged,
    this.label,
  });

  final List<String> initial;
  final List<String>? suggestions;
  final ValueChanged<List<String>>? onChanged;
  final String? label;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> _items = widget.initial;

  @override
  Widget build(BuildContext context) => SettingsStringListEditor(
    label: widget.label,
    items: _items,
    addLabel: 'Add module',
    addHint: 'SNI id or title',
    suggestions: widget.suggestions,
    onChanged: (next) {
      widget.onChanged?.call(next);
      setState(() => _items = next);
    },
  );
}

final Finder _grip = findGlyph(ShellGlyph.dragHandle);

void main() {
  test('reorderedList moves an element to its landing index', () {
    expect(reorderedList(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
    expect(reorderedList(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    expect(reorderedList(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
    final inPlace = ['a', 'b', 'c'];
    reorderInPlace(inPlace, 0, 1);
    expect(inPlace, ['b', 'a', 'c']);
  });

  testWidgets('the add row is the last row, under every item', (tester) async {
    await _pump(
      tester,
      const _Host(
        initial: ['clock', 'workspaces', 'battery'],
        suggestions: ['clock', 'workspaces', 'battery', 'weather'],
      ),
    );
    final adder = tester.getRect(find.text('Add module'));
    for (final item in ['clock', 'workspaces', 'battery']) {
      expect(
        adder.top,
        greaterThan(tester.getRect(find.text(item)).bottom),
        reason: 'the add row is above "$item"',
      );
    }
  });

  testWidgets('each row carries its position, in order', (tester) async {
    await _pump(tester, const _Host(initial: ['clock', 'workspaces']));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(
      tester.getRect(find.text('1')).center.dy,
      closeTo(tester.getRect(find.text('clock')).center.dy, 2),
    );
    expect(
      tester.getRect(find.text('2')).center.dy,
      closeTo(tester.getRect(find.text('workspaces')).center.dy, 2),
    );
  });

  testWidgets('each row removes itself', (tester) async {
    List<String>? emitted;
    await _pump(
      tester,
      _Host(
        initial: const ['clock', 'workspaces', 'battery'],
        onChanged: (next) => emitted = next,
      ),
    );
    final removes = find.byWidgetPredicate(
      (w) => w is SettingsIconButton && w.icon == ShellGlyph.close,
    );
    expect(removes, findsNWidgets(3));
    await tester.tap(removes.at(1));
    await tester.pump();
    expect(emitted, ['clock', 'battery']);
    expect(find.text('workspaces'), findsNothing);
  });

  testWidgets('a row dragged down lands where it is dropped', (tester) async {
    List<String>? emitted;
    await _pump(
      tester,
      _Host(
        initial: const ['clock', 'workspaces', 'battery'],
        onChanged: (next) => emitted = next,
      ),
    );
    final from = tester.getCenter(find.text('clock'));
    final target = tester.getCenter(find.text('workspaces'));
    final gesture = await tester.startGesture(from);
    // Past the drag slop first, then on until the held row's centre is past
    // the next row's.
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(Offset(from.dx, target.dy + 6));
    await tester.pump();
    // While held, the numbers say where each row is going.
    expect(
      tester.getRect(find.text('2')).center.dy,
      closeTo(tester.getRect(find.text('clock')).center.dy, 2),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(emitted, ['workspaces', 'clock', 'battery']);
    expect(
      tester.getRect(find.text('workspaces')).top,
      lessThan(tester.getRect(find.text('clock')).top),
    );
  });

  testWidgets('a row dragged up past two lands at the top', (tester) async {
    List<String>? emitted;
    await _pump(
      tester,
      _Host(
        initial: const ['clock', 'workspaces', 'battery'],
        onChanged: (next) => emitted = next,
      ),
    );
    final from = tester.getCenter(find.text('battery'));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveTo(Offset(from.dx, from.dy - 200));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(emitted, ['battery', 'clock', 'workspaces']);
  });

  testWidgets('a drag dropped where it started writes nothing', (tester) async {
    var writes = 0;
    await _pump(
      tester,
      _Host(initial: const ['clock', 'workspaces'], onChanged: (_) => writes++),
    );
    final from = tester.getCenter(find.text('clock'));
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveTo(from);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(writes, 0);
  });

  testWidgets('the free-form adder becomes a field in its own row', (
    tester,
  ) async {
    List<String>? emitted;
    await _pump(
      tester,
      _Host(initial: const ['discord'], onChanged: (next) => emitted = next),
    );
    expect(find.text('SNI id or title'), findsNothing);
    final adder = tester.getRect(find.text('Add module'));

    await tester.tap(find.text('Add module'));
    await tester.pump();
    expect(find.text('SNI id or title'), findsOneWidget);
    // Where the add row was: under the rows, not over them.
    expect(
      tester.getRect(find.text('SNI id or title')).top,
      greaterThan(tester.getRect(find.text('discord')).bottom),
    );
    expect(
      tester.getRect(find.text('SNI id or title')).center.dy,
      closeTo(adder.center.dy, 6),
    );

    await tester.enterText(find.byType(EditableText), 'steam');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(emitted, ['discord', 'steam']);
    // Still open, for the next one — and still the last row.
    expect(find.byType(EditableText), findsOneWidget);
    expect(
      tester.getRect(find.byType(EditableText)).top,
      greaterThan(tester.getRect(find.text('steam')).bottom),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('Add module'), findsOneWidget);
  });

  testWidgets('the dropdown adder offers the suggestions and adds one', (
    tester,
  ) async {
    List<String>? emitted;
    await _pump(
      tester,
      _Host(
        initial: const ['clock'],
        suggestions: const ['clock', 'weather'],
        onChanged: (next) => emitted = next,
      ),
    );
    await tester.tap(find.text('Add module'));
    await tester.pumpAndSettle();
    expect(find.text('weather'), findsOneWidget);
    await tester.tap(find.text('weather'));
    await tester.pumpAndSettle();
    expect(emitted, ['clock', 'weather']);
  });

  testWidgets('the add row fires from every corner', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      SettingsList(
        itemCount: 0,
        itemBuilder: (_, _) => const SizedBox(),
        adder: SettingsListAddRow(label: 'Add', onTap: () => taps++),
      ),
    );
    await tapEveryCorner(tester, find.byType(SettingsListAddRow));
    expect(taps, 4);
  });

  testWidgets('an empty list says so above its adder', (tester) async {
    await _pump(tester, const _Host(initial: []));
    expect(find.text('Nothing here yet.'), findsOneWidget);
    expect(
      tester.getRect(find.text('Add module')).top,
      greaterThan(tester.getRect(find.text('Nothing here yet.')).bottom),
    );
  });

  testWidgets('the box fills the height it is given', (tester) async {
    await _pump(
      tester,
      const _Host(initial: ['clock', 'workspaces']),
      minHeight: 360,
    );
    expect(tester.getSize(find.byType(SettingsList)).height, 360);
    // The rows stay at the top of it.
    expect(tester.getRect(find.text('clock')).top, lessThan(40));
  });

  testWidgets('under a label, the box takes what the label leaves', (
    tester,
  ) async {
    await _pump(
      tester,
      const _Host(label: 'Left modules', initial: ['clock']),
      minHeight: 360,
    );
    final list = tester.getRect(find.byType(SettingsList));
    expect(
      list.top,
      greaterThan(tester.getRect(find.text('Left modules')).bottom),
    );
    expect(list.bottom, closeTo(360, 0.5));
  });

  testWidgets('a list grows past the room rather than clipping', (
    tester,
  ) async {
    await _pump(
      tester,
      _Host(initial: [for (var i = 0; i < 12; i++) 'item $i']),
      minHeight: 100,
    );
    expect(tester.getSize(find.byType(SettingsList)).height, greaterThan(100));
    expect(find.text('item 11'), findsOneWidget);
  });

  testWidgets('an unordered list shows neither grips nor numbers', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsList(
        itemCount: 2,
        onRemove: (_) {},
        itemBuilder: (_, i) => Text('pin $i'),
        adder: SettingsListAddRow(label: 'Add', onTap: () {}),
      ),
    );
    expect(find.text('1'), findsNothing);
    expect(
      _grip,
      findsNothing,
    );
  });

  testWidgets('a handle-only row does not drag from its content', (
    tester,
  ) async {
    var moves = 0;
    await _pump(
      tester,
      SettingsList(
        itemCount: 2,
        handleOnly: true,
        onReorder: (_, _) => moves++,
        itemBuilder: (_, i) => Text('card $i'),
        adder: SettingsListAddRow(label: 'Add', onTap: () {}),
      ),
    );
    final content = tester.getCenter(find.text('card 0'));
    await tester.dragFrom(content, const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(moves, 0);

    // The grip does.
    final grip = tester.getCenter(
      _grip.first,
    );
    final gesture = await tester.startGesture(grip);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(moves, 1);
  });

  testWidgets('nothing animates once a drag is over', (tester) async {
    await _pump(
      tester,
      const _Host(initial: ['clock', 'workspaces', 'battery']),
    );
    await tester.dragFrom(
      tester.getCenter(find.text('clock')),
      const Offset(0, 50),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the Input Sources adder is the list\'s last row', (
    tester,
  ) async {
    await _pump(
      tester,
      SettingsList(
        itemCount: 1,
        itemBuilder: (_, _) => const Text('English (US)'),
        adder: InputSourcePicker(
          catalog: parseXkbRulesList('! layout\n  us  English (US)\n'),
          existing: const [InputSource('us')],
          onSelected: (_) {},
        ),
      ),
    );
    final adder = tester.getRect(find.text('Add Input Source'));
    expect(
      adder.top,
      greaterThan(tester.getRect(find.text('English (US)')).bottom),
    );
  });
}
