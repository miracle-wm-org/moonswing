import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/desktop/desktop_menu.dart';
import 'package:graceful_shell/scopes.dart';

/// The menus are pumped bare, with no PanelWindowManager: the popup machinery
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
}) {
  return DesktopItemMenu(
    item: item,
    onOpen: onOpen ?? () {},
    onOpenWith: onOpenWith ?? (_) {},
    onRename: onRename ?? () {},
    onRemove: onRemove ?? () {},
    handlers: handlers ?? () => const [],
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
  });
}
