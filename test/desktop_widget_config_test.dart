import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/config.dart';

void main() {
  group('DesktopWidgetItem.fromMap', () {
    test('defaults everything but the type', () {
      final widget = DesktopWidgetItem.fromMap({'type': 'media_player'})!;
      expect(widget.type, 'media_player');
      // An entry a user hand-wrote gets an id derived from its type rather than
      // being dropped over a bookkeeping field they never see.
      expect(widget.id, 'media_player');
      expect((widget.column, widget.row), (0, 0));
      expect((widget.columnSpan, widget.rowSpan), (1, 1));
      expect(widget.options, isEmpty);
    });

    test('returns null for an entry that names no type', () {
      expect(DesktopWidgetItem.fromMap({'id': 'a'}), isNull);
      expect(DesktopWidgetItem.fromMap({'type': ''}), isNull);
      expect(DesktopWidgetItem.fromMap({'type': '  '}), isNull);
      expect(DesktopWidgetItem.fromMap({'type': 7}), isNull);
    });

    // A widget occupying no cells is invisible *and* unclickable — there would
    // be nothing left to remove it with.
    test('a zero or negative span floors at one cell', () {
      final widget = DesktopWidgetItem.fromMap({
        'type': 'media_player',
        'column_span': 0,
        'row_span': -3,
      })!;
      expect((widget.columnSpan, widget.rowSpan), (1, 1));
    });

    test('a wrongly typed field costs that key, not the entry', () {
      final widget = DesktopWidgetItem.fromMap({
        'type': 'media_player',
        'column': 'over there',
        'row': 2,
      })!;
      expect((widget.column, widget.row), (0, 2));
    });

    test('reads the options table, and omits an empty one on the way out', () {
      final widget = DesktopWidgetItem.fromMap({
        'type': 'media_player',
        'options': {'format': '24h'},
      })!;
      expect(widget.options['format'], '24h');
      expect(widget.toMap()['options'], {'format': '24h'});

      const bare = DesktopWidgetItem(id: 'a', type: 'media_player');
      expect(bare.toMap().containsKey('options'), isFalse);
    });

    test('round-trips through toMap', () {
      const widget = DesktopWidgetItem(
        id: 'media_player-2',
        type: 'media_player',
        column: 1,
        row: 2,
        columnSpan: 3,
        rowSpan: 2,
      );
      expect(DesktopWidgetItem.fromMap(widget.toMap()), widget);
    });
  });

  group('DesktopConfig.fromMap', () {
    test('parses the widget list in document order', () {
      final config = DesktopConfig.fromMap({
        'widgets': [
          {'type': 'media_player', 'id': 'a'},
          {'type': 'media_player', 'id': 'b', 'column': 2},
        ],
      });
      expect(config.widgets.map((w) => w.id), ['a', 'b']);
      expect(config.widgets.last.column, 2);
    });

    // Ids are what a drag, a resize and a removal name: two widgets answering
    // to one id would move together and remove together.
    test('renames a duplicate id rather than dropping the widget', () {
      final config = DesktopConfig.fromMap({
        'widgets': [
          {'type': 'media_player'},
          {'type': 'media_player'},
          {'type': 'media_player', 'id': 'media_player-2'},
        ],
      });
      expect(
        config.widgets.map((w) => w.id),
        ['media_player', 'media_player-2', 'media_player-3'],
      );
    });

    test('a widgets key that is not a list costs the widgets, not the grid',
        () {
      final config = DesktopConfig.fromMap({
        'cell_width': 120.0,
        'widgets': 'nonsense',
      });
      expect(config.widgets, isEmpty);
      expect(config.cellWidth, 120);
    });

    test('an absent widgets key is an empty list, and the default config has none',
        () {
      expect(DesktopConfig.fromMap(const {}).widgets, isEmpty);
      expect(const DesktopConfig().widgets, isEmpty);
    });

    test('equality covers the widget list', () {
      const a = DesktopConfig(
        widgets: [DesktopWidgetItem(id: 'a', type: 'media_player')],
      );
      const b = DesktopConfig(
        widgets: [DesktopWidgetItem(id: 'a', type: 'media_player')],
      );
      const c = DesktopConfig(
        widgets: [
          DesktopWidgetItem(id: 'a', type: 'media_player', columnSpan: 2),
        ],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('copyWith carries the list it was not given', () {
      const config = DesktopConfig(
        items: [DesktopItem(kind: DesktopItemKind.file, target: '/a')],
        widgets: [DesktopWidgetItem(id: 'a', type: 'media_player')],
      );
      expect(config.copyWith(items: const []).widgets, config.widgets);
      expect(config.copyWith(widgets: const []).items, config.items);
    });
  });
}
