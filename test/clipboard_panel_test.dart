// The clipboard history panel and the bar button that opens it: what is drawn,
// what a click does, how it leaves, and that it is still at rest.

import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/clipboard/clipboard_config.dart';
import 'package:moonswing/clipboard/clipboard_entry.dart';
import 'package:moonswing/clipboard/clipboard_panel.dart';
import 'package:moonswing/clipboard/clipboard_panel_controller.dart';
import 'package:moonswing/clipboard/clipboard_store.dart';
import 'package:moonswing/clipboard/wl_clipboard.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/modules/clipboard.dart';
import 'package:moonswing/scopes.dart';

import 'clipboard_fakes.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: DefaultTextStyle(
    style: const TextStyle(fontSize: 14),
    child: ThemeScope(
      theme: const ThemeConfig(),
      child: MediaQuery(
        data: const MediaQueryData(size: Size(360, 800)),
        child: child,
      ),
    ),
  ),
);

void main() {
  late Directory dir;
  late FakeClipboard clipboard;
  late ClipboardHistoryStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clipboard_panel');
    clipboard = FakeClipboard();
    store = ClipboardHistoryStore.forTesting(
      backend: clipboard,
      directory: '${dir.path}/clipboard',
      clock: () => DateTime(2026, 10, 15, 9, 30),
    );
    // Not persisted: a debounced save is a timer the fake clock would hold
    // open past the test, and saving is the store test's business.
    store.configure(const ClipboardConfig(persist: false));
  });

  tearDown(() async {
    store.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Starts the history and copies [texts] in order, outside the fake clock:
  /// the store reads and writes real files.
  Future<void> seed(WidgetTester tester, List<Object> offers) async {
    await tester.runAsync(() async {
      store.acquire();
      await settle();
      for (final offer in offers) {
        clipboard.offer(
          offer is String
              ? {'text/plain;charset=utf-8': offer}
              : offer as Map<String, Object>,
        );
        clipboard.emit();
        await settle();
      }
    });
    addTearDown(store.release);
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    ValueNotifier<bool>? closing,
    VoidCallback? onClosed,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final notifier = closing ?? ValueNotifier(false);
    if (closing == null) addTearDown(notifier.dispose);
    await tester.pumpWidget(
      _host(
        ClipboardPanel(
          side: ClipboardSide.left,
          closingNotifier: notifier,
          onClosed: onClosed ?? () {},
          store: store,
          now: () => DateTime(2026, 10, 15, 12),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists what was copied, newest first, and comes to rest', (
    tester,
  ) async {
    await seed(tester, [
      'first thing',
      {'text/uri-list': 'file:///home/me/holiday.mp4\r\n'},
      'second thing',
    ]);
    await pumpPanel(tester);

    expect(find.text('Clipboard'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);
    final cards = tester
        .widgetList<ClipboardCard>(find.byType(ClipboardCard))
        .map((c) => c.entry.kind)
        .toList();
    expect(cards, [
      ClipboardKind.text,
      ClipboardKind.files,
      ClipboardKind.text,
    ]);
    expect(find.text('second thing'), findsOneWidget);
    expect(find.text('holiday.mp4'), findsOneWidget);
    expect(find.textContaining('Video file'), findsOneWidget);
    // Nothing animates while the panel just sits there.
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('a click on a card copies it; its buttons do not', (
    tester,
  ) async {
    await seed(tester, ['older', 'newer']);
    await pumpPanel(tester);

    await tester.tap(find.text('older'));
    await tester.pump();
    expect(clipboard.written, hasLength(1));
    expect(String.fromCharCodes(clipboard.written.single.$2), 'older');
    expect(store.entries.first.text, 'older', reason: 'moved to the top');
    expect(find.text('Copied'), findsOneWidget);

    // The flash goes on its own.
    await tester.pump(kClipboardCopiedFlash);
    expect(find.text('Copied'), findsNothing);

    final pin = find.descendant(
      of: find.byType(ClipboardCard).first,
      matching: find.byIcon(FontAwesomeIcons.thumbtack.data),
    );
    await tester.tap(pin);
    await tester.pump();
    expect(store.entries.first.pinned, isTrue);
    expect(clipboard.written, hasLength(1), reason: 'pinning copies nothing');

    final trash = find.descendant(
      of: find.byType(ClipboardCard).last,
      matching: find.byIcon(FontAwesomeIcons.trashCan.data),
    );
    await tester.tap(trash);
    await tester.pump();
    expect(store.entries.map((e) => e.text), ['older']);
    expect(clipboard.written, hasLength(1));
  });

  testWidgets(
    'Clear keeps the pinned, and goes when nothing is left to clear',
    (tester) async {
      await seed(tester, ['a', 'b']);
      store.togglePin(store.entries.last);
      await pumpPanel(tester);

      expect(find.text('2 items, 1 pinned'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(store.entries.map((e) => e.text), ['a']);
      expect(find.text('Clear'), findsNothing);
    },
  );

  testWidgets('the close button plays the exit, then closes once', (
    tester,
  ) async {
    await seed(tester, const []);
    final closing = ValueNotifier(false);
    addTearDown(closing.dispose);
    var closed = 0;
    await pumpPanel(tester, closing: closing, onClosed: () => closed++);

    expect(find.text('Nothing copied yet'), findsWidgets);
    await tester.tap(find.byIcon(FontAwesomeIcons.xmark.data));
    await tester.pump();
    expect(closing.value, isTrue);
    expect(closed, 0, reason: 'not torn down under its own animation');

    await tester.pumpAndSettle();
    expect(closed, 1);
    closing.value = false;
    closing.value = true;
    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('a dead watcher says why and offers a retry', (tester) async {
    await seed(tester, ['kept']);
    await tester.runAsync(() async {
      clipboard.fail(
        const ClipboardWatchFailure(
          'The clipboard history needs wl-paste, from the wl-clipboard package.',
          missing: true,
        ),
      );
      await settle();
    });
    await pumpPanel(tester);

    expect(find.text('Clipboard history stopped'), findsOneWidget);
    expect(find.textContaining('wl-clipboard'), findsOneWidget);
    // What was recorded before is still there.
    expect(find.text('kept'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.runAsync(settle);
    await tester.pump();
    expect(find.text('Clipboard history stopped'), findsNothing);
    expect(clipboard.watching, isTrue);
  });

  group('ClipboardButton', () {
    testWidgets('holds a lease while it is on a bar', (tester) async {
      final controller = ClipboardPanelController.forTesting();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(ClipboardButton(controller: controller, store: store)),
      );
      expect(store.leaseCount, 1);
      await tester.pumpWidget(_host(const SizedBox()));
      expect(store.leaseCount, 0);
      await tester.runAsync(settle);
    });

    testWidgets('a press asks the root to toggle the panel', (tester) async {
      final controller = ClipboardPanelController.forTesting();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          Center(
            child: ClipboardButton(controller: controller, store: store),
          ),
        ),
      );
      await tester.tap(find.byType(ClipboardButton));
      expect(controller.signalCount, 1);

      // Drawn pressed while the root reports the panel up.
      controller.setOpen(true);
      await tester.pump();
      expect(controller.isOpen.value, isTrue);
      await tester.pumpWidget(_host(const SizedBox()));
      await tester.runAsync(settle);
    });
  });
}
