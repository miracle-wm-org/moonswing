import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart' show Surface;

import 'package:moonswing/claude/claude_account_store.dart';
import 'package:moonswing/claude/claude_api.dart';
import 'package:moonswing/claude/claude_catalog.dart';
import 'package:moonswing/claude/claude_chat_store.dart';
import 'package:moonswing/claude/claude_key_store.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/modules/claude.dart';
import 'package:moonswing/overlay/settings/accounts/claude_account.dart';
import 'package:moonswing/scopes.dart';

import 'claude_fakes.dart';

/// A reply that builds a small form: a text field bound to `/name` and a
/// button that sends it back.
String formReply() {
  final create = {
    'version': 'v0.9',
    'createSurface': {
      'surfaceId': 'form',
      'catalogId': kClaudeCatalogId,
      'sendDataModel': true,
    },
  };
  final components = {
    'version': 'v0.9',
    'updateComponents': {
      'surfaceId': 'form',
      'components': [
        {
          'id': 'root',
          'component': 'Column',
          'children': ['title', 'name', 'send'],
        },
        {
          'id': 'title',
          'component': 'Text',
          'text': 'Your name',
          'variant': 'h3',
        },
        {
          'id': 'name',
          'component': 'TextField',
          'label': 'Name',
          'value': {'path': '/name'},
        },
        {
          'id': 'send',
          'component': 'Button',
          'child': 'send_label',
          'variant': 'primary',
          'action': {
            'event': {
              'name': 'submit_name',
              'context': {
                'name': {'path': '/name'},
              },
            },
          },
        },
        {'id': 'send_label', 'component': 'Text', 'text': 'Send'},
      ],
    },
  };
  return 'A form:\n```json\n${jsonEncode(create)}\n```\n'
      '```json\n${jsonEncode(components)}\n```\n';
}

/// Waits, on the real clock, for [condition] — at most two seconds.
Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

List<ClaudeEvent> reply(String text, {String stop = 'end_turn'}) => [
  // Split mid-way, as a real stream is.
  ClaudeTextDelta(text.substring(0, text.length ~/ 2)),
  ClaudeTextDelta(text.substring(text.length ~/ 2)),
  ClaudeStopped(stop),
];

void main() {
  late Directory tempDir;
  late FakeClaudeClient client;
  late ClaudeAccountStore account;
  late ClaudeChatStore chat;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('moonswing-claude');
    client = FakeClaudeClient();
    account = ClaudeAccountStore.forTesting(
      client: client,
      keys: ClaudeKeyStore(directory: tempDir.path),
    );
    chat = ClaudeChatStore.forTesting(account);
  });

  tearDown(() {
    chat.dispose();
    account.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('the account', () {
    test('a key is checked, kept at 0600, and read back', () async {
      await account.signIn('  sk-ant-api03-secret-key-1234 ');
      expect(account.signedIn, isTrue);
      expect(client.verified, ['sk-ant-api03-secret-key-1234']);
      final file = File('${tempDir.path}/anthropic-api-key');
      expect(file.readAsStringSync().trim(), 'sk-ant-api03-secret-key-1234');
      expect(file.statSync().mode & 0x1FF, 0x180);

      final again = ClaudeAccountStore.forTesting(
        client: client,
        keys: ClaudeKeyStore(directory: tempDir.path),
      );
      addTearDown(again.dispose);
      await again.load();
      expect(again.signedIn, isTrue);
      expect(again.keyHint, 'sk-ant-api03-…1234');
    });

    test('a rejected key is not kept, and says why', () async {
      client.verifyError = const ClaudeAuthException();
      await account.signIn('sk-ant-wrong');
      expect(account.signedIn, isFalse);
      expect(account.error, contains('not accepted'));
      expect(File('${tempDir.path}/anthropic-api-key').existsSync(), isFalse);
    });

    test('a key rejected later signs the shell out', () async {
      await account.signIn('sk-ant-api03-secret-key-1234');
      await expectLater(
        account.withKey<void>((_) async => throw const ClaudeAuthException()),
        throwsA(isA<ClaudeAuthException>()),
      );
      expect(account.signedIn, isFalse);
      expect(account.error, isNotEmpty);
    });
  });

  group('the conversation', () {
    setUp(() => account.seed());

    test('a question streams an answer and joins the history', () async {
      client.answers.add(reply('Paris is the capital.'));
      await chat.ask('Capital of France?');
      await pumpEventQueue();

      final answer = chat.items.last as ClaudeAnswer;
      expect(answer.state, ClaudeAnswerState.done);
      expect(
        answer.parts.whereType<ClaudeAnswerText>().single.text,
        'Paris is the capital.',
      );
      expect(chat.history, const [
        ClaudeTurn.user('Capital of France?'),
        ClaudeTurn.assistant('Paris is the capital.'),
      ]);
      expect(client.requests.single.model, kClaudeDefaultModel);
      // The UI half is in the prompt, and the persona leads it.
      expect(client.requests.single.system, startsWith('You are Claude'));
      expect(client.requests.single.system, contains(kClaudeCatalogId));
    });

    test('with generate_ui off the prompt carries no catalogue', () async {
      chat.configure(const ClaudeConfig(generateUi: false, effort: 'low'));
      await chat.ask('hi');
      await pumpEventQueue();
      expect(client.requests.single.system, isNot(contains(kClaudeCatalogId)));
      expect(client.requests.single.effort, 'low');
    });

    test('an A2UI block becomes a surface in the answer', () async {
      client.answers.add(reply(formReply()));
      await chat.ask('Ask me my name');
      await pumpEventQueue();

      final answer = chat.items.last as ClaudeAnswer;
      expect(answer.parts.first, isA<ClaudeAnswerText>());
      expect(
        answer.parts.whereType<ClaudeAnswerSurface>().single.surfaceId,
        'form',
      );
      expect(chat.controller.activeSurfaceIds, contains('form'));
      // What Claude wrote goes back verbatim, JSON and all.
      expect(chat.history.last.text, formReply());
    });

    test('a refusal takes the question back out of the history', () async {
      client.answers.add(reply('Partial', stop: 'refusal'));
      await chat.ask('something');
      await pumpEventQueue();
      final answer = chat.items.last as ClaudeAnswer;
      expect(answer.state, ClaudeAnswerState.refused);
      expect(chat.history, isEmpty);
    });

    test('a rejected key fails the answer and signs out', () async {
      client.answers.add(const []);
      client.streamError = const ClaudeAuthException();
      await chat.ask('q');
      await pumpEventQueue();
      final answer = chat.items.last as ClaudeAnswer;
      expect(answer.state, ClaudeAnswerState.failed);
      expect(answer.needsAccount, isTrue);
      expect(account.signedIn, isFalse);
      expect(chat.history, isEmpty);
    });

    test('a retryable failure is retried in place', () async {
      client.answers.add(const []);
      client.streamError = const ClaudeException('busy', retryable: true);
      await chat.ask('q');
      await pumpEventQueue();
      expect((chat.items.last as ClaudeAnswer).retryable, isTrue);

      await chat.retry();
      await pumpEventQueue();
      expect(chat.items, hasLength(2));
      expect((chat.items.last as ClaudeAnswer).state, ClaudeAnswerState.done);
      expect(chat.history.first, const ClaudeTurn.user('q'));
    });

    test('stop keeps what arrived on screen and out of the history', () async {
      client.gate = Completer<void>();
      final asked = chat.ask('long');
      await pumpEventQueue();
      expect(chat.busy, isTrue);
      chat.stop();
      await asked;
      expect(chat.busy, isFalse);
      expect(
        (chat.items.last as ClaudeAnswer).state,
        ClaudeAnswerState.stopped,
      );
      expect(chat.history, isEmpty);
      client.gate!.complete();
    });

    test('no account is an answer that says where to link one', () async {
      account.seed(stage: ClaudeAuthStage.signedOut);
      await chat.ask('q');
      final answer = chat.items.last as ClaudeAnswer;
      expect(answer.needsAccount, isTrue);
      expect(client.requests, isEmpty);
    });

    test('clear forgets everything', () async {
      client.answers.add(reply(formReply()));
      await chat.ask('form');
      await pumpEventQueue();
      chat.clear();
      expect(chat.items, isEmpty);
      expect(chat.history, isEmpty);
      expect(chat.controller.activeSurfaceIds, isEmpty);
    });
  });

  test('an interaction is labelled by its action, an error not at all', () {
    expect(
      claudeInteractionLabel(
        '{"version":"v0.9","action":{"name":"submit_name"}}',
      ),
      'submit name',
    );
    expect(claudeInteractionLabel('{"version":"v0.9","error":{}}'), isNull);
    expect(claudeInteractionLabel('nope'), isNull);
  });

  group('the popup', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        ThemeScope(
          theme: const ThemeConfig(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: kClaudePopupWidth,
              height: kClaudePopupHeight,
              child: ClaudePopup(chat: chat, openAccounts: () {}),
            ),
          ),
        ),
      );
    }

    testWidgets('signed out, it sends the user to Accounts', (tester) async {
      account.seed(stage: ClaudeAuthStage.signedOut);
      await pump(tester);
      expect(find.text('Connect Claude'), findsOneWidget);
      expect(find.text('Open Accounts settings'), findsOneWidget);
    });

    testWidgets('a generated form is drawn, and its button answers back', (
      tester,
    ) async {
      account.seed();
      client.answers.add(reply(formReply()));
      await pump(tester);
      expect(find.textContaining('Ask a quick question'), findsOneWidget);

      await tester.runAsync(() async {
        await chat.ask('Ask me my name');
        await pumpEventQueue();
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(Surface), findsOneWidget);
      expect(find.text('Your name'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);

      await tester.enterText(find.byType(EditableText).first, 'Ada');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.runAsync(() => pumpEventQueue());
      await tester.pump();

      // The press became the next turn, carrying the bound value.
      expect(client.requests, hasLength(2));
      final turn = client.requests.last.messages.last;
      expect(turn.role, 'user');
      expect(turn.text, contains('submit_name'));
      expect(turn.text, contains('Ada'));
      expect(find.text('submit name'), findsOneWidget);
    });
  });

  testWidgets('the Accounts card links a pasted key, and unlinks it', (
    tester,
  ) async {
    await tester.pumpWidget(
      ThemeScope(
        theme: const ThemeConfig(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            child: ClaudeAccountCard(account: account),
          ),
        ),
      ),
    );
    await tester.runAsync(account.load);
    await tester.pump();
    expect(find.text('Get a key in the Console'), findsOneWidget);

    await tester.enterText(
      find.byType(EditableText),
      'sk-ant-api03-pasted-key-9876',
    );
    // Linking writes the key file: real I/O, waited for on the real clock.
    await tester.runAsync(() async {
      await tester.tap(find.text('Link'));
      await until(() => account.signedIn);
    });
    await tester.pump();
    expect(account.signedIn, isTrue);
    expect(find.text('sk-ant-api03-…9876'), findsOneWidget);

    await tester.runAsync(() async {
      // Signing out publishes once the key file is gone.
      final published = Completer<void>();
      void done() {
        if (!published.isCompleted) published.complete();
      }

      account.addListener(done);
      await tester.tap(find.text('Unlink'));
      await published.future.timeout(const Duration(seconds: 2));
      account.removeListener(done);
    });
    await tester.pump();
    expect(account.signedIn, isFalse);
    expect(find.text('Link'), findsOneWidget);
  });
}
