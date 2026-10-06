import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/accounts/accounts_scope.dart';
import 'package:moonswing/caldav/caldav_account_store.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/github/github_account_store.dart';
import 'package:moonswing/github/github_api.dart';
import 'package:moonswing/github/github_link_store.dart';
import 'package:moonswing/github/github_token_store.dart';
import 'package:moonswing/modules/todo.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/todo/todo_backup_panel.dart';
import 'package:moonswing/todo/todo_caldav_sync.dart';
import 'package:moonswing/todo/todo_controller.dart';
import 'package:moonswing/todo/todo_database.dart';
import 'package:moonswing/todo/todo_model.dart';
import 'package:moonswing/todo/todo_overlay.dart';
import 'package:moonswing/todo/todo_standup_panel.dart';
import 'package:moonswing/todo/todo_store.dart';

import 'github_fakes.dart';

TodoItem _item(
  String id,
  TodoColumn column, {
  DateTime? due,
  List<TodoMove>? history,
}) => TodoItem(
  id: id,
  title: 'Card $id',
  body: 'Body of $id',
  column: column,
  created: DateTime(2026, 9, 20, 10),
  due: due,
  history:
      history ??
      [TodoMove(from: null, to: column, at: DateTime(2026, 9, 20, 10))],
);

/// The text of the standup summary on show.
String standupText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byType(SelectableRegion),
        matching: find.byType(Text),
      ),
    )
    .textSpan!
    .toPlainText();

/// The middle of the one stretch of text [finder] finds.
Offset centreOf(FinderBase<TextRangeContext> finder) {
  final range = finder.evaluate().single;
  final boxes = range.renderObject.getBoxesForSelection(
    TextSelection(
      baseOffset: range.textRange.start,
      extentOffset: range.textRange.end,
    ),
  );
  return range.renderObject.localToGlobal(boxes.first.toRect().center);
}

Future<void> sendCtrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  late ValueNotifier<bool> closing;
  late int closed;
  late DateTime now;

  setUp(() {
    closing = ValueNotifier(false);
    closed = 0;
    now = DateTime(2026, 9, 24, 12);
  });

  tearDown(() => closing.dispose());

  Future<TodoStore> pump(
    WidgetTester tester,
    List<TodoItem> items, {
    bool inMemory = false,
    ValueChanged<String>? onOpenLink,
    VoidCallback? onOpenAccounts,
    ValueChanged<TodoCalDavSync>? withSync,
    GithubLinkStore? githubLinks,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = TodoStore.forTesting(
      items: items,
      now: () => now,
      inMemory: inMemory,
    );
    addTearDown(store.dispose);
    // Never the shell's own: that one reads the real account file.
    final sync = TodoCalDavSync.forTesting(
      store: store,
      accounts: CalDavAccountStore.forTesting(
        directory: '${Directory.systemTemp.path}/todo-overlay-no-account',
      ),
      now: () => now,
    );
    addTearDown(sync.dispose);
    withSync?.call(sync);
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: AccountsScope(
          githubLinks: githubLinks,
          child: TodoOverlay(
            closingNotifier: closing,
            onClosed: () => closed++,
            store: store,
            sync: sync,
            onOpenAccounts: onOpenAccounts ?? () {},
            onOpenLink: onOpenLink ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('draws the five columns and their cards', (tester) async {
    await pump(tester, [
      _item('a', TodoColumn.inbox),
      _item('b', TodoColumn.inProgress, due: DateTime(2026, 9, 24)),
    ]);
    for (final column in TodoColumn.values) {
      // "Todo" is also the board's own heading.
      expect(
        find.text(column.label),
        findsNWidgets(column == TodoColumn.todo ? 2 : 1),
      );
    }
    expect(find.text('Card a'), findsOneWidget);
    expect(find.text('Body of a'), findsOneWidget);
    // The due chip reads relative to today.
    expect(find.text('Today'), findsOneWidget);
    // When the card arrived in its column.
    expect(find.text('20 Sep 2026, 10:00'), findsNWidgets(2));
  });

  testWidgets('a calendar card is marked in its calendar\'s colour', (
    tester,
  ) async {
    TodoItem meeting(String id, String? color) =>
        _item(id, TodoColumn.todo).copyWith(
          external: TodoExternal(
            source: TodoExternal.googleCalendar,
            key: 'work/$id',
            title: 'Card $id',
            start: DateTime(2026, 9, 24, 15),
            end: DateTime(2026, 9, 24, 16),
            calendar: color == null ? null : 'Work',
            color: color,
          ),
        );
    await pump(tester, [
      meeting('m', '#ff0000'),
      meeting('n', null),
      _item('a', TodoColumn.todo),
    ]);
    // The calendar is named on the card, and the icon beside it is its colour.
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    final icons = tester
        .widgetList<FaIcon>(find.byIcon(FontAwesomeIcons.calendar.data))
        .map((i) => i.color)
        .toList();
    const theme = ThemeConfig();
    expect(icons, containsAll([const Color(0xFFFF0000), theme.accent]));

    expect(
      calendarCardColor(meeting('m', '#ff0000'), theme),
      const Color(0xFFFF0000),
    );
    expect(calendarCardColor(meeting('n', null), theme), theme.accent);
    expect(calendarCardColor(meeting('x', 'nonsense'), theme), theme.accent);
    expect(calendarCardColor(_item('a', TodoColumn.todo), theme), isNull);
  });

  testWidgets('the add button creates an item in its own column', (
    tester,
  ) async {
    final store = await pump(tester, []);
    // The fourth column's plus: Finished.
    final adds = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == 'SettingsIconButton',
    );
    expect(adds, findsNWidgets(TodoColumn.values.length));
    await tester.tap(adds.at(TodoColumn.values.indexOf(TodoColumn.finished)));
    await tester.pumpAndSettle();
    expect(find.text('New item'), findsOneWidget);

    // The editor's title field; the first EditableText is the board's search.
    await tester.enterText(find.byType(EditableText).at(1), 'Write report');
    await tester.pump();
    await tester.tap(find.text('Tomorrow'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final item = store.itemsIn(TodoColumn.finished).single;
    expect(item.title, 'Write report');
    expect(item.due, DateTime(2026, 9, 25));
    expect(find.text('New item'), findsNothing);
    expect(find.text('Write report'), findsOneWidget);
  });

  testWidgets('a card dragged onto another column moves there, with the time', (
    tester,
  ) async {
    final store = await pump(tester, [_item('a', TodoColumn.inbox)]);
    now = DateTime(2026, 9, 24, 15, 30);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card a')),
    );
    await tester.pump();
    // Onto the empty In Progress column's placeholder.
    await gesture.moveTo(tester.getCenter(find.text('Drop a card here').at(1)));
    await tester.pump();
    await gesture.moveBy(const Offset(4, 4));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final moved = store.item('a')!;
    expect(moved.column, TodoColumn.inProgress);
    expect(moved.history.last.from, TodoColumn.inbox);
    expect(moved.history.last.at, DateTime(2026, 9, 24, 15, 30));
  });

  testWidgets('a card dropped on another card lands above it', (tester) async {
    final store = await pump(tester, [
      _item('a', TodoColumn.inbox),
      _item('b', TodoColumn.todo),
      _item('c', TodoColumn.todo),
    ]);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card a')),
    );
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Card c')));
    await tester.pump();
    await gesture.moveBy(const Offset(2, 2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(store.itemsIn(TodoColumn.todo).map((i) => i.id), ['b', 'a', 'c']);
  });

  testWidgets('clicking a card opens it with its history', (tester) async {
    await pump(tester, [
      _item(
        'a',
        TodoColumn.inProgress,
        history: [
          TodoMove(
            from: null,
            to: TodoColumn.inbox,
            at: DateTime(2026, 9, 20, 10),
          ),
          TodoMove(
            from: TodoColumn.inbox,
            to: TodoColumn.inProgress,
            at: DateTime(2026, 9, 22, 8, 5),
          ),
        ],
      ),
    ]);
    await tester.tap(find.text('Card a'));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);
    expect(find.text('Created in Inbox'), findsOneWidget);
    expect(find.text('Inbox → In Progress'), findsOneWidget);
    expect(find.text('22 Sep 2026, 08:05'), findsWidgets);
  });

  testWidgets('a link in a card opens its address, not the card', (
    tester,
  ) async {
    final opened = <String>[];
    await pump(tester, [
      TodoItem(
        id: 'a',
        title: 'Read https://example.com/title',
        body: 'Notes at www.example.org/notes.',
        column: TodoColumn.inbox,
        created: DateTime(2026, 9, 20, 10),
      ),
    ], onOpenLink: opened.add);

    // Taps the middle of the character at [offset] in [text].
    Future<void> tapCharacter(String text, int offset) async {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(text, findRichText: true),
      );
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: offset, extentOffset: offset + 1),
          )
          .single;
      await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();
    }

    await tapCharacter('Read https://example.com/title', 12);
    await tapCharacter('Notes at www.example.org/notes.', 12);
    expect(opened, [
      'https://example.com/title',
      'https://www.example.org/notes',
    ]);
    expect(find.text('Edit item'), findsNothing);

    // The words before the link still open the card.
    await tapCharacter('Read https://example.com/title', 1);
    expect(find.text('Edit item'), findsOneWidget);
    expect(opened, hasLength(2));
  });

  testWidgets('a GitHub link is its title, and still opens the address', (
    tester,
  ) async {
    final tokens = Directory.systemTemp.createTempSync('todo-github-');
    addTearDown(() => tokens.deleteSync(recursive: true));
    final client = FakeGithubClient()
      ..issues['o/r/12'] = const GithubIssue(
        number: 12,
        title: 'Fix the thing',
        state: GithubIssueState.open,
        isPullRequest: true,
      );
    final account = GithubAccountStore.forTesting(
      client: client,
      tokens: GithubTokenStore(directory: tokens.path),
    )..seed();
    addTearDown(account.dispose);
    final links = GithubLinkStore.forTesting(account: account);
    addTearDown(links.dispose);
    const url = 'https://github.com/o/r/pull/12';
    final opened = <String>[];
    await pump(
      tester,
      [
        TodoItem(
          id: 'a',
          title: 'Review $url',
          body: 'and https://github.com/o/r/issues/99 too',
          column: TodoColumn.inbox,
          created: DateTime(2026, 9, 20, 10),
        ),
      ],
      onOpenLink: opened.add,
      githubLinks: links,
    );

    expect(find.text('Fix the thing #12', findRichText: true), findsOneWidget);
    // A link GitHub would not answer for is still a chip, by its number.
    expect(find.text('r#99', findRichText: true), findsOneWidget);
    expect(find.textContaining(url, findRichText: true), findsNothing);

    await tester.tap(find.text('Fix the thing #12', findRichText: true));
    await tester.pumpAndSettle();
    expect(opened, [url]);
    expect(find.text('Edit item'), findsNothing);

    // Signed out, the address is the address again.
    account.seed(stage: GithubAuthStage.signedOut);
    await tester.pumpAndSettle();
    expect(find.text('Fix the thing #12', findRichText: true), findsNothing);
    expect(find.text('Review $url', findRichText: true), findsOneWidget);
  });

  testWidgets('Escape closes the editor, then the board', (tester) async {
    await pump(tester, [_item('a', TodoColumn.inbox)]);
    await tester.tap(find.text('Card a'));
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Edit item'), findsNothing);
    expect(closing.value, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closing.value, isTrue);
    expect(closed, 1);
  });

  testWidgets('the board says where its backup is, and opens Backups', (
    tester,
  ) async {
    final store = await pump(tester, [_item('a', TodoColumn.inbox)]);
    final footer = find.textContaining('Backed up to ');
    expect(footer, findsOneWidget);
    final path = displayPath(store.backupPath);
    expect(tester.widget<Text>(footer).data, contains(path));

    await tester.tap(find.text('Backups…'));
    await tester.pumpAndSettle();
    expect(find.text('Backup file'), findsOneWidget);
    expect(find.text(path), findsOneWidget);
    expect(find.text('Keep a copy somewhere else'), findsOneWidget);
    expect(find.textContaining('git init'), findsOneWidget);

    // Escape backs out of Backups before it closes the board.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Backup file'), findsNothing);
    expect(closing.value, isFalse);
  });

  testWidgets('Backups offers a task list, and sends the user to sign in', (
    tester,
  ) async {
    var opened = 0;
    await pump(tester, const [], onOpenAccounts: () => opened++);
    await tester.tap(find.text('Backups…'));
    await tester.pumpAndSettle();
    expect(find.text('Task list'), findsOneWidget);
    expect(find.text('No CalDAV server is signed in to.'), findsOneWidget);
    await tester.tap(find.text('Set up in Settings…'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    // Settings opens over where the board was.
    expect(closing.value, isTrue);
  });

  testWidgets('a linked board says so, and why a sync did not get through', (
    tester,
  ) async {
    late TodoCalDavSync sync;
    final store = await pump(tester, const [], withSync: (s) => sync = s);
    await tester.runAsync(
      () => store.linkRemote(
        const TodoRemoteLink(url: 'https://dav.example.com/t/', name: 'Home'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('synced with Home'), findsOneWidget);

    await tester.tap(find.text('Backups…'));
    await tester.pumpAndSettle();
    expect(find.text('Not synced yet.'), findsOneWidget);
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();
    expect(sync.error, contains('Settings › Accounts'));
    expect(find.textContaining('Not signed in'), findsOneWidget);
    expect(find.textContaining('Home could not be synced'), findsOneWidget);
  });

  testWidgets('the standup card takes a summary since the last one', (
    tester,
  ) async {
    final store = await pump(tester, [
      _item(
        'done',
        TodoColumn.finished,
        history: [TodoMove(from: null, to: TodoColumn.finished, at: now)],
      ),
      _item('doing', TodoColumn.inProgress),
      _item('next', TodoColumn.todo),
    ]);
    final button = find.byWidgetPredicate(
      (w) => w is FaIcon && w.icon == FontAwesomeIcons.bullhorn.data,
    );
    // Opening the card takes nothing; its own button does.
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsOneWidget);
    expect(store.standups, isEmpty);
    expect(store.lastStandup, isNull);
    expect(find.textContaining('No summaries yet'), findsOneWidget);
    await tester.tap(find.text('New summary'));
    await tester.pumpAndSettle();
    final report = standupText(tester);
    expect(report, startsWith('Done:\n• Card done'));
    expect(report, contains('In progress:\n• Card doing'));
    expect(report, contains('To do:\n• Card next'));
    expect(store.lastStandup, now);
    // Copying is selecting; there is no button for it, nor for forgetting one.
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Invalidate'), findsNothing);

    // Escape closes the summary before it closes the board.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Standup'), findsNothing);
    expect(closing.value, isFalse);

    // Reopening shows the kept summary without taking another.
    now = now.add(const Duration(hours: 1));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(store.standups, hasLength(1));
    expect(standupText(tester), contains('Done:\n• Card done'));

    // The next one counts from the first: nothing new has been finished.
    await tester.tap(find.text('New summary'));
    await tester.pumpAndSettle();
    expect(standupText(tester), contains('Done:\n• Nothing finished'));

    // Both are listed; picking the older one shows it.
    expect(store.standups, hasLength(2));
    expect(find.text('Latest'), findsOneWidget);
    await tester.tap(find.text('Today at 12:00'));
    await tester.pumpAndSettle();
    expect(standupText(tester), contains('Done:\n• Card done'));
  });

  testWidgets('a summary is selected and copied in place, its links live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = TodoStore.forTesting(
      items: [
        _item(
          'doing',
          TodoColumn.inProgress,
        ).copyWith(title: 'Review https://example.com/pr/1 today'),
      ],
      now: () => now,
      inMemory: true,
    );
    addTearDown(store.dispose);
    final copied = <String>[];
    var result = ClipboardResult.copied;
    final opened = <String>[];
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => TodoStandupLayer(
                  store: store,
                  onDone: () {},
                  onOpenLink: opened.add,
                  copy: (text) async {
                    copied.add(text);
                    return result;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('New summary'));
    await tester.pumpAndSettle();
    final report = standupText(tester);
    expect(report, contains('• Review https://example.com/pr/1 today'));

    // A click on the address opens it.
    final link = find.textRange.ofSubstring(
      'https://example.com/pr/1',
      descendentOf: find.byType(SelectableRegion),
    );
    await tester.tapAt(centreOf(link), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(opened, ['https://example.com/pr/1']);

    // A drag selects; Ctrl+C hands the selection to the clipboard helper.
    final word = find.textRange.ofSubstring(
      'In progress',
      descendentOf: find.byType(SelectableRegion),
    );
    final range = word.evaluate().single;
    final boxes = range.renderObject.getBoxesForSelection(
      TextSelection(
        baseOffset: range.textRange.start,
        extentOffset: range.textRange.end,
      ),
    );
    final from = range.renderObject.localToGlobal(
      boxes.first.toRect().centerLeft + const Offset(1, 0),
    );
    final to = range.renderObject.localToGlobal(
      boxes.last.toRect().centerRight,
    );
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await sendCtrl(tester, LogicalKeyboardKey.keyC);
    expect(copied, ['In progress']);

    // Ctrl+A takes all of it.
    await sendCtrl(tester, LogicalKeyboardKey.keyA);
    await sendCtrl(tester, LogicalKeyboardKey.keyC);
    expect(copied.last, report);

    expect(find.textContaining('wl-clipboard'), findsNothing);

    // A copy that fails says why.
    result = ClipboardResult.unavailable;
    await sendCtrl(tester, LogicalKeyboardKey.keyC);
    expect(find.text('Install wl-clipboard to copy it.'), findsOneWidget);
  });

  Finder searchField() => find.byType(EditableText).first;

  testWidgets('searching filters every column down to the matches', (
    tester,
  ) async {
    await pump(tester, [
      _item('a', TodoColumn.inbox),
      _item('b', TodoColumn.todo).copyWith(title: 'Fix the Bluetooth bug'),
      _item('c', TodoColumn.finished),
    ], inMemory: true);
    expect(find.text('Card a'), findsOneWidget);

    // The middle of a word, in the wrong case.
    await tester.enterText(searchField(), 'LUETOO');
    await tester.pumpAndSettle();
    expect(find.text('Card a'), findsNothing);
    expect(find.text('Fix the Bluetooth bug'), findsOneWidget);
    expect(find.text('Card c'), findsNothing);
    expect(find.text('1 match'), findsOneWidget);
    expect(
      find.text('No matches'),
      findsNWidgets(TodoColumn.values.length - 1),
    );

    // Every body says "Body of".
    await tester.enterText(searchField(), 'ody of');
    await tester.pumpAndSettle();
    expect(find.text('3 matches'), findsOneWidget);

    await tester.enterText(searchField(), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('Fix the Bluetooth bug'), findsNothing);
    // Every column, and the count in the header.
    expect(
      find.text('No matches'),
      findsNWidgets(TodoColumn.values.length + 1),
    );
  });

  testWidgets('a card edited while searching joins the results', (
    tester,
  ) async {
    final store = await pump(tester, [
      _item('a', TodoColumn.inbox),
      _item('b', TodoColumn.inbox),
    ], inMemory: true);
    await tester.enterText(searchField(), 'dentist');
    await tester.pumpAndSettle();
    expect(find.text('Card a'), findsNothing);

    store.update(
      'a',
      title: 'Card a',
      body: 'Ring the dentist',
      column: TodoColumn.inbox,
      due: null,
      recurrence: null,
    );
    await tester.pumpAndSettle();
    expect(find.text('Card a'), findsOneWidget);
    expect(find.text('Card b'), findsNothing);
  });

  testWidgets('Escape clears the search before it closes the board', (
    tester,
  ) async {
    await pump(tester, [_item('a', TodoColumn.inbox)]);
    await tester.enterText(searchField(), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Card a'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Card a'), findsOneWidget);
    expect(closing.value, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closing.value, isTrue);
  });

  testWidgets('overdue cards sit at the top of an open column', (tester) async {
    await pump(tester, [
      _item('a', TodoColumn.todo),
      _item('b', TodoColumn.todo, due: DateTime(2026, 9, 22)),
    ]);
    expect(
      tester.getTopLeft(find.text('Card b')).dy,
      lessThan(tester.getTopLeft(find.text('Card a')).dy),
    );
  });

  testWidgets('Finished folds earlier days away; a click opens one', (
    tester,
  ) async {
    TodoItem finished(String id, DateTime at) => _item(
      id,
      TodoColumn.finished,
      history: [TodoMove(from: null, to: TodoColumn.finished, at: at)],
    );
    await pump(tester, [
      finished('today', DateTime(2026, 9, 24, 9)),
      finished('yesterday', DateTime(2026, 9, 23, 9)),
      finished('older', DateTime(2026, 9, 20, 9)),
    ]);
    expect(find.text('Card today'), findsOneWidget);
    expect(find.text('Card yesterday'), findsNothing);
    expect(find.text('Card older'), findsNothing);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('20 Sep 2026'), findsOneWidget);

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    expect(find.text('Card yesterday'), findsOneWidget);
    expect(find.text('Card older'), findsNothing);

    await tester.tap(find.text('Yesterday'));
    await tester.pumpAndSettle();
    expect(find.text('Card yesterday'), findsNothing);
  });

  testWidgets('Abandoned folds every day, today too', (tester) async {
    await pump(tester, [
      _item(
        'a',
        TodoColumn.abandoned,
        history: [
          TodoMove(
            from: null,
            to: TodoColumn.abandoned,
            at: DateTime(2026, 9, 24, 9),
          ),
        ],
      ),
    ]);
    expect(find.text('Card a'), findsNothing);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Card a'), findsOneWidget);
  });

  testWidgets('a search opens the folded day holding a match', (tester) async {
    await pump(tester, [
      _item('a', TodoColumn.finished).copyWith(title: 'Renew passport'),
      _item('b', TodoColumn.finished),
    ], inMemory: true);
    expect(find.text('Renew passport'), findsNothing);

    // Closed by hand first: a search still opens it.
    await tester.tap(find.text('20 Sep 2026'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20 Sep 2026'));
    await tester.pumpAndSettle();

    await tester.enterText(searchField(), 'passport');
    await tester.pumpAndSettle();
    expect(find.text('Renew passport'), findsOneWidget);
    expect(find.text('Card b'), findsNothing);

    await tester.enterText(searchField(), '');
    await tester.pumpAndSettle();
    expect(find.text('Renew passport'), findsNothing);
  });

  testWidgets('a repeating item shows when its next copy comes', (
    tester,
  ) async {
    final store = await pump(tester, [_item('a', TodoColumn.todo)]);
    await tester.tap(find.text('Card a'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'SettingsToggle',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('The next one is on'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final rule = store.item('a')!.recurrence!;
    expect(rule.every, 1);
    expect(rule.unit, RecurrenceUnit.weeks);
    // The card being edited stands for today; the first copy is a week out.
    expect(rule.next, DateTime(2026, 10, 1));
  });

  testWidgets('the bar button asks for the board on its own output', (
    tester,
  ) async {
    final controller = TodoController.forTesting();
    addTearDown(controller.dispose);
    final store = TodoStore.forTesting(
      items: [_item('a', TodoColumn.todo, due: DateTime(2026, 9, 23))],
      now: () => now,
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: TodoButton(controller: controller, store: store),
          ),
        ),
      ),
    );
    // One overdue item.
    expect(find.text('1'), findsOneWidget);
    var signals = 0;
    controller.addListener(() => signals++);
    await tester.tap(find.byType(TodoButton));
    expect(signals, 1);
    // No DisplayScope above it: the root falls back to the focused output.
    expect(controller.output, isNull);
  });
}
