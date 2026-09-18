import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/desktop/desktop_menu.dart';
import 'package:graceful_shell/desktop/widgets/desktop_widget.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';

/// The menus are pumped bare, with no WindowManager: the popup machinery
/// belongs to the host, and these are the cards it puts inside one.
Future<void> pumpMenu(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontSize: 14),
        child: ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 320, height: 420, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const DesktopItem _file = DesktopItem(
  kind: DesktopItemKind.file,
  target: '/home/me/notes.txt',
);

const DesktopItem _app = DesktopItem(
  kind: DesktopItemKind.app,
  target: '/usr/share/applications/firefox.desktop',
);

DesktopItemMenu _menu({
  DesktopItem item = _file,
  VoidCallback? onOpen,
  void Function(AppEntry)? onOpenWith,
  VoidCallback? onRename,
  VoidCallback? onRemove,
  List<AppEntry> Function()? handlers,
  int selectionCount = 1,
}) {
  return DesktopItemMenu(
    item: item,
    onOpen: onOpen ?? () {},
    onOpenWith: onOpenWith ?? (_) {},
    onRename: onRename ?? () {},
    onRemove: onRemove ?? () {},
    handlers: handlers ?? () => const [],
    selectionCount: selectionCount,
  );
}

void main() {
  group('DesktopItemMenu', () {
    testWidgets('offers the four actions for a file', (tester) async {
      await pumpMenu(tester, _menu());
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Open with…'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Remove from desktop'), findsOneWidget);
    });

    // With a band selection the rows that only make sense for one icon go
    // away, and the destructive one says how much it will take.
    testWidgets('counts the selection and drops the single-item rows',
        (tester) async {
      await pumpMenu(tester, _menu(selectionCount: 3));
      expect(find.text('Open 3 items'), findsOneWidget);
      expect(find.text('Remove 3 items from desktop'), findsOneWidget);
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Open with…'), findsNothing);
    });

    // "Open with" is meaningless for an application: the row is absent rather
    // than disabled, because there is nothing for it to mean.
    testWidgets('omits Open with for an application', (tester) async {
      await pumpMenu(tester, _menu(item: _app));
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Open with…'), findsNothing);
    });

    testWidgets('each row reports its action', (tester) async {
      var opened = 0;
      var renamed = 0;
      var removed = 0;
      await pumpMenu(
        tester,
        _menu(
          onOpen: () => opened++,
          onRename: () => renamed++,
          onRemove: () => removed++,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.tap(find.text('Rename'));
      await tester.tap(find.text('Remove from desktop'));
      await tester.pump();

      expect((opened, renamed, removed), (1, 1, 1));
    });

    // A second page of the same popup, not a child surface — a nested popup
    // would be a separate Wayland surface with its own pointer-crossing
    // problems, for no benefit when the pages are mutually exclusive.
    testWidgets('Open with swaps the card for a handler page, and back',
        (tester) async {
      var resolved = 0;
      await pumpMenu(tester, _menu(handlers: () {
        resolved++;
        return const [];
      }));

      await tester.tap(find.text('Open with…'));
      await tester.pump();

      expect(resolved, 1);
      expect(find.text('Open notes.txt with'), findsOneWidget);
      expect(find.text('Remove from desktop'), findsNothing);
      expect(find.text('Back'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('Remove from desktop'), findsOneWidget);
    });

    testWidgets('an empty handler list says so rather than showing a blank card',
        (tester) async {
      await pumpMenu(tester, _menu());
      await tester.tap(find.text('Open with…'));
      await tester.pump();
      expect(find.text('No applications available'), findsOneWidget);
    });

    // The handlers carry live GAppInfo pointers the host owns, so the menu must
    // ask for them only when the page is actually opened.
    testWidgets('does not resolve handlers until asked', (tester) async {
      var resolved = 0;
      await pumpMenu(tester, _menu(handlers: () {
        resolved++;
        return const [];
      }));
      expect(resolved, 0);
    });
  });

  group('DesktopEmptyMenu', () {
    testWidgets('offers the four empty-space actions and reports each',
        (tester) async {
      final tapped = <String>[];
      await pumpMenu(
        tester,
        DesktopEmptyMenu(
          onAddApplication: () => tapped.add('app'),
          onAddFile: () => tapped.add('file'),
          onOrganize: () => tapped.add('organize'),
          onChangeBackground: () => tapped.add('background'),
        ),
      );

      await tester.tap(find.text('Add application…'));
      await tester.tap(find.text('Add file or folder…'));
      await tester.tap(find.text('Organize'));
      await tester.tap(find.text('Change background…'));
      await tester.pump();

      expect(tapped, ['app', 'file', 'organize', 'background']);
    });
  });

  group('DesktopMenuCard', () {
    // Shown greyed rather than hidden, so the menu's shape does not change and
    // the user can see what is unavailable.
    testWidgets('a disabled row renders but does not fire', (tester) async {
      var tapped = 0;
      await pumpMenu(
        tester,
        DesktopMenuCard(entries: [
          DesktopMenuEntry(
            label: 'Nope',
            enabled: false,
            onTap: () => tapped++,
          ),
        ]),
      );

      expect(find.text('Nope'), findsOneWidget);
      await tester.tap(find.text('Nope'));
      await tester.pump();
      expect(tapped, 0);
    });

    // The other half of that rule: a row saying "this is what you already have"
    // is *marked*, not greyed and not hidden, so a set of alternatives keeps its
    // shape as the pointer moves through it.
    testWidgets('a selected row is accented, checked, and still fires',
        (tester) async {
      var tapped = 0;
      const theme = ThemeConfig();
      await pumpMenu(
        tester,
        DesktopMenuCard(entries: [
          DesktopMenuEntry(
            label: 'Chosen',
            icon: FontAwesomeIcons.tableCells,
            selected: true,
            onTap: () => tapped++,
          ),
          DesktopMenuEntry(label: 'Other', onTap: () {}),
        ]),
      );

      // The check, because a theme is free to make its accent quiet — and the
      // accent, because the check alone is easy to miss.
      expect(find.byIcon(FontAwesomeIcons.check.data), findsOneWidget);
      expect(
        tester
            .widget<FaIcon>(find.byIcon(FontAwesomeIcons.tableCells.data))
            .color,
        theme.accentText,
      );

      // Re-choosing what is already chosen is a no-op, not an error: the row
      // stays live so the menu can be dismissed by clicking it.
      await tester.tap(find.text('Chosen'));
      await tester.pump();
      expect(tapped, 1);
    });

    testWidgets('the mark gives way to the hover fill it would sit on',
        (tester) async {
      await pumpMenu(
        tester,
        DesktopMenuCard(entries: [
          DesktopMenuEntry(
            label: 'Chosen',
            icon: FontAwesomeIcons.tableCells,
            selected: true,
            onTap: () {},
          ),
        ]),
      );

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(pointer.removePointer);
      await pointer.addPointer(location: Offset.zero);
      await tester.pump();
      await pointer.moveTo(tester.getCenter(find.text('Chosen')));
      await tester.pump();

      // `surface_hover` is the accent itself in the shipped palette, and no
      // lift off a surface clears that surface's own colour — so the hovered
      // row is lettered in the ordinary foreground and the check is what goes
      // on saying "current".
      const theme = ThemeConfig();
      expect(
        tester
            .widget<FaIcon>(find.byIcon(FontAwesomeIcons.tableCells.data))
            .color,
        theme.popupForeground,
      );
      expect(find.byIcon(FontAwesomeIcons.check.data), findsOneWidget);
    });
  });

  group('DesktopEmptyMenu widgets page', () {
    final spec = DesktopWidgetSpec(
      type: 'fake',
      name: 'Fake widget',
      icon: FontAwesomeIcons.shapes,
      builder: (context, widget) => const SizedBox.shrink(),
    );

    // A build with no widget types has nothing to offer, and a disabled row
    // would be a promise with nothing behind it.
    testWidgets('hides "Add widget…" when the registry is empty',
        (tester) async {
      await pumpMenu(
        tester,
        DesktopEmptyMenu(
          onAddApplication: () {},
          onAddFile: () {},
          onOrganize: () {},
          onChangeBackground: () {},
        ),
      );
      expect(find.text('Add widget…'), findsNothing);
    });

    testWidgets('lists the specs on a second page and reports the pick',
        (tester) async {
      DesktopWidgetSpec? picked;
      await pumpMenu(
        tester,
        DesktopEmptyMenu(
          widgetSpecs: [spec],
          onAddWidget: (s) => picked = s,
          onAddApplication: () {},
          onAddFile: () {},
          onOrganize: () {},
          onChangeBackground: () {},
        ),
      );

      await tester.tap(find.text('Add widget…'));
      await tester.pump();
      expect(find.text('Add widget'), findsOneWidget);
      expect(find.text('Organize'), findsNothing);

      await tester.tap(find.text('Fake widget'));
      await tester.pump();
      expect(picked?.type, 'fake');
    });

    testWidgets('Back returns to the first page', (tester) async {
      await pumpMenu(
        tester,
        DesktopEmptyMenu(
          widgetSpecs: [spec],
          onAddWidget: (_) {},
          onAddApplication: () {},
          onAddFile: () {},
          onOrganize: () {},
          onChangeBackground: () {},
        ),
      );

      await tester.tap(find.text('Add widget…'));
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('Organize'), findsOneWidget);
    });
  });

  group('DesktopWidgetMenu', () {
    final spec = DesktopWidgetSpec(
      type: 'fake',
      name: 'Fake widget',
      icon: FontAwesomeIcons.shapes,
      minSpan: (columns: 2, rows: 1),
      maxSpan: (columns: 4, rows: 3),
      builder: (context, widget) => const SizedBox.shrink(),
    );

    const item = DesktopWidgetItem(
      id: 'fake',
      type: 'fake',
      columnSpan: 3,
      rowSpan: 2,
    );

    testWidgets('removes, and offers a reset to the type default',
        (tester) async {
      var removed = 0;
      var reset = 0;
      await pumpMenu(
        tester,
        DesktopWidgetMenu(
          item: item,
          spec: spec,
          onRemove: () => removed++,
          onResetSize: () => reset++,
        ),
      );

      expect(find.text('Fake widget'), findsOneWidget);
      await tester.tap(find.text('Reset size'));
      await tester.tap(find.text('Remove widget'));
      await tester.pump();
      expect((reset, removed), (1, 1));
    });

    testWidgets('the reset is disabled at the default size', (tester) async {
      var reset = 0;
      await pumpMenu(
        tester,
        DesktopWidgetMenu(
          item: const DesktopWidgetItem(
            id: 'fake',
            type: 'fake',
            columnSpan: 2,
            rowSpan: 1,
          ),
          spec: spec,
          onRemove: () {},
          onResetSize: () => reset++,
        ),
      );

      await tester.tap(find.text('Reset size'));
      await tester.pump();
      expect(reset, 0);
    });

    // A placeholder for a type this build does not have still has to be
    // removable, and has no default size to reset to.
    testWidgets('an unknown type offers removal only', (tester) async {
      var removed = 0;
      await pumpMenu(
        tester,
        DesktopWidgetMenu(
          item: const DesktopWidgetItem(id: 'x', type: 'from_the_future'),
          spec: null,
          onRemove: () => removed++,
        ),
      );

      expect(find.text('Reset size'), findsNothing);
      await tester.tap(find.text('Remove widget'));
      await tester.pump();
      expect(removed, 1);
    });
  });

  group('one card, two shapes', () {
    // DesktopMenuCard serves both the desktop's cursor menu and the dock's
    // unpin menu, and those are opened by different hosts: the dock's goes
    // through openBarPopup and attaches to the bar, the desktop's is anchored
    // to the pointer and has no panel edge to attach to. The card itself knows
    // nothing about either — PopupAttachScope is what tells it apart.
    BoxDecoration decorationOf(WidgetTester tester) =>
        tester.widget<Container>(find.byType(Container).first).decoration
            as BoxDecoration;

    testWidgets('anchored to the pointer, it floats', (tester) async {
      await pumpMenu(
        tester,
        DesktopMenuCard(entries: [DesktopMenuEntry(label: 'A', onTap: () {})]),
      );
      final decoration = decorationOf(tester);
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect((decoration.border! as Border).top.style, BorderStyle.solid);
    });

    testWidgets('opened from the bar, it joins it', (tester) async {
      await pumpMenu(
        tester,
        PopupAttachScope(
          edge: 'bottom',
          child: DesktopMenuCard(
            entries: [DesktopMenuEntry(label: 'A', onTap: () {})],
          ),
        ),
      );
      final decoration = decorationOf(tester);
      final radius = decoration.borderRadius! as BorderRadius;
      expect(radius.bottomLeft, Radius.zero);
      expect(radius.topLeft, const Radius.circular(8));
      expect((decoration.border! as Border).bottom.style, BorderStyle.none);
    });
  });
}
