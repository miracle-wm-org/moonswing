// The one conversation with Claude, and the UI it has generated.
//
// A store rather than popup state for the reason `GithubAccountStore` owns its
// sign-in: the popup is a window that comes and goes, and closing it half-way
// through an answer must not lose the answer — reopening it shows the same
// conversation, still streaming if it was. Nothing here runs at rest: no timer,
// no connection, nothing until a question is asked.
//
// The genui half is its engine, not its facade. A `SurfaceController` holds
// every surface Claude has created, over the shell's own catalogue
// (`claude_catalog.dart`), and the popup renders each one with genui's
// `Surface`. What feeds it is `ClaudeReplySplitter` rather than genui's
// `Conversation`/`A2uiTransportAdapter` pair: that pair runs one parser over
// the whole reply, which holds prose back at every stray brace, and it has no
// notion of *which* answer a surface belongs to — and in a chat the surface
// belongs under the sentence that introduced it. So the splitter hands genui's
// parser exactly the A2UI fences, and places each created surface in the
// answer at the point it was written.
//
// Going back the other way is genui's too: a button in a generated UI
// dispatches an action, the controller turns it into a `ChatMessage` on
// `onSubmit`, and that becomes the next user turn — the loop that lets a
// generated form be filled in and sent.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:genui/genui.dart';

import 'package:moonswing/claude/claude_account_store.dart';
import 'package:moonswing/claude/claude_api.dart';
import 'package:moonswing/claude/claude_catalog.dart';
import 'package:moonswing/claude/claude_config.dart';
import 'package:moonswing/claude/claude_reply.dart';

/// One entry in the conversation.
sealed class ClaudeChatItem {
  const ClaudeChatItem();
}

/// Something the user said — typed, or done in a generated UI.
class ClaudeQuestion extends ClaudeChatItem {
  const ClaudeQuestion(this.text, {this.fromUi = false});

  final String text;

  /// True when this is a button pressed in a generated UI rather than a
  /// question typed into the field; the popup draws it smaller.
  final bool fromUi;
}

/// How an answer ended, or that it has not.
enum ClaudeAnswerState {
  streaming,
  done,

  /// Cut off at the output cap; what arrived is kept.
  truncated,

  /// The user pressed Stop.
  stopped,

  /// Declined by the model or a safety classifier.
  refused,

  /// The request failed; [ClaudeAnswer.error] says why.
  failed,
}

/// A piece of an answer as the popup draws it: text, or a generated surface.
sealed class ClaudeAnswerPart {
  const ClaudeAnswerPart();
}

class ClaudeAnswerText extends ClaudeAnswerPart {
  const ClaudeAnswerText(this.text);

  final String text;
}

class ClaudeAnswerSurface extends ClaudeAnswerPart {
  const ClaudeAnswerSurface(this.surfaceId);

  final String surfaceId;
}

/// One answer, growing while it streams.
///
/// Its own [ChangeNotifier] — the per-item notifier the repaint rules ask for —
/// so a token arriving rebuilds the one answer it belongs to, not the
/// conversation, and not the question field under it.
class ClaudeAnswer extends ClaudeChatItem with ChangeNotifier {
  ClaudeAnswer();

  final List<ClaudeAnswerPart> _parts = [];
  List<ClaudeAnswerPart> get parts => List.unmodifiable(_parts);

  ClaudeAnswerState _state = ClaudeAnswerState.streaming;
  ClaudeAnswerState get state => _state;

  bool get streaming => _state == ClaudeAnswerState.streaming;

  String _error = '';
  String get error => _error;

  /// Whether the failure is one a retry could fix.
  bool _retryable = false;
  bool get retryable => _retryable;

  /// Whether the failure is that there is no account, which Settings fixes.
  bool _needsAccount = false;
  bool get needsAccount => _needsAccount;

  /// The model that actually answered, when it is not the one asked — a
  /// server-side fallback after a classifier declined.
  String _servedBy = '';
  String get servedBy => _servedBy;

  /// Whether anything is on screen yet.
  bool get isEmpty => _parts.isEmpty;

  void _addText(String text) {
    if (text.isEmpty) return;
    final last = _parts.isEmpty ? null : _parts.last;
    if (last is ClaudeAnswerText) {
      _parts[_parts.length - 1] = ClaudeAnswerText(last.text + text);
    } else {
      // Leading whitespace after a surface is the gap the fence left.
      final trimmed = last is ClaudeAnswerSurface ? text.trimLeft() : text;
      if (trimmed.isEmpty) return;
      _parts.add(ClaudeAnswerText(trimmed));
    }
    notifyListeners();
  }

  void _addSurface(String id) {
    _parts.add(ClaudeAnswerSurface(id));
    notifyListeners();
  }

  void _served(String model) {
    _servedBy = model;
    notifyListeners();
  }

  void _finish(
    ClaudeAnswerState state, {
    String error = '',
    bool retryable = false,
    bool needsAccount = false,
  }) {
    _state = state;
    _error = error;
    _retryable = retryable;
    _needsAccount = needsAccount;
    notifyListeners();
  }
}

/// The conversation.
class ClaudeChatStore extends ChangeNotifier {
  ClaudeChatStore._(this.account);

  static final ClaudeChatStore instance = ClaudeChatStore._(
    ClaudeAccountStore.instance,
  );

  /// A detached store for tests, over an account whose client is a fake.
  @visibleForTesting
  factory ClaudeChatStore.forTesting(ClaudeAccountStore account) =>
      ClaudeChatStore._(account);

  final ClaudeAccountStore account;

  ClaudeConfig _config = const ClaudeConfig();
  ClaudeConfig get config => _config;

  /// `[modules.claude]`, pushed here by the module's `fromMap`. Read per
  /// question, so a change applies to the next one.
  void configure(ClaudeConfig config) => _config = config;

  /// The catalogue every surface is built from.
  final Catalog catalog = claudeShellCatalog();

  SurfaceController? _controller;
  StreamSubscription<ChatMessage>? _submissions;

  /// The engine holding every generated surface. Made on first use, and
  /// replaced by [clear].
  SurfaceController get controller {
    final existing = _controller;
    if (existing != null) return existing;
    final made = SurfaceController(catalogs: [catalog]);
    _submissions = made.onSubmit.listen(_onSubmit);
    return _controller = made;
  }

  final Map<String, SurfaceContext> _contexts = {};

  /// The context the popup renders [surfaceId] from — one per surface, rather
  /// than a new one per rebuild.
  SurfaceContext surfaceContext(String surfaceId) =>
      _contexts.putIfAbsent(surfaceId, () => controller.contextFor(surfaceId));

  final List<ClaudeChatItem> _items = [];
  List<ClaudeChatItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// What the API is sent: the turns so far, text only. Append-only — a turn
  /// that failed is taken back off the end, never edited in the middle.
  final List<ClaudeTurn> _history = [];

  @visibleForTesting
  List<ClaudeTurn> get history => List.unmodifiable(_history);

  StreamSubscription<ClaudeEvent>? _stream;
  ClaudeAnswer? _current;

  bool get busy => _current != null;

  /// The turn to send again after a retryable failure.
  ClaudeTurn? _failedTurn;

  /// UI interactions that arrived while an answer was streaming, sent once it
  /// ends.
  final List<String> _pendingInteractions = [];

  /// Whether the answer streaming now was sent automatically to repair a UI
  /// the last one got wrong. One repair per question: a model that writes an
  /// invalid UI twice is told the second time by the user, not by a loop that
  /// spends their money.
  bool _repairing = false;

  // --- asking --------------------------------------------------------------

  /// Asks [text].
  Future<void> ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || busy) return;
    _items.add(ClaudeQuestion(question));
    _repairing = false;
    await _send(ClaudeTurn.user(question));
  }

  /// Sends the turn that last failed again.
  Future<void> retry() async {
    final turn = _failedTurn;
    if (turn == null || busy) return;
    // The failed answer is replaced, not stacked under a second one.
    if (_items.isNotEmpty && _items.last is ClaudeAnswer) _items.removeLast();
    await _send(turn);
  }

  /// Stops the answer streaming now. What arrived stays on screen but is not
  /// sent back: half an answer — maybe half a UI — is not a turn to build on.
  void stop() {
    final answer = _current;
    if (answer == null) return;
    unawaited(_stream?.cancel());
    _stream = null;
    _current = null;
    _history.removeLast();
    _failedTurn = null;
    answer._finish(ClaudeAnswerState.stopped);
    notifyListeners();
  }

  /// Starts over: forgets the conversation and every surface in it.
  void clear() {
    if (busy) stop();
    _items.clear();
    _history.clear();
    _pendingInteractions.clear();
    _failedTurn = null;
    unawaited(_submissions?.cancel());
    _submissions = null;
    _contexts.clear();
    _controller?.dispose();
    _controller = null;
    notifyListeners();
  }

  String get _system {
    final today = DateTime.now().toIso8601String().split('T').first;
    final fragments = [
      claudePersona(generateUi: _config.generateUi),
      'Current date: $today',
    ];
    if (!_config.generateUi) return fragments.join('\n\n');
    return PromptBuilder.chat(
      catalog: catalog,
      systemPromptFragments: fragments,
    ).systemPromptJoined();
  }

  Future<void> _send(ClaudeTurn turn) async {
    final answer = ClaudeAnswer();
    _items.add(answer);
    _current = answer;
    _failedTurn = null;
    _history.add(turn);
    notifyListeners();

    final key = await account.currentKey();
    if (_current != answer) return;
    if (key == null) {
      _fail(
        answer,
        turn,
        'Link a Claude API key under Settings › Accounts to ask a question.',
        needsAccount: true,
      );
      return;
    }

    final splitter = ClaudeReplySplitter();
    final raw = StringBuffer();
    var stopReason = '';
    final model = _config.model;

    _stream = account.client
        .stream(
          key: key,
          model: model,
          system: _system,
          messages: List.of(_history),
          effort: _config.effort,
        )
        .listen(
          (event) {
            switch (event) {
              case ClaudeTextDelta(:final text):
                raw.write(text);
                splitter.add(text).forEach((p) => _apply(answer, p));
              case ClaudeModelServed(model: final served):
                if (served != model) answer._served(served);
              case ClaudeStopped(stopReason: final reason):
                stopReason = reason;
            }
          },
          onError: (Object e) {
            if (_current != answer) return;
            if (e is ClaudeAuthException) {
              unawaited(account.reportRejected(key));
              _fail(answer, turn, e.message, needsAccount: true);
            } else if (e is ClaudeException) {
              _fail(answer, turn, e.message, retryable: e.retryable);
            } else {
              debugPrint('claude: $e');
              _fail(answer, turn, 'Something went wrong', retryable: true);
            }
          },
          onDone: () {
            if (_current != answer) return;
            splitter.close().forEach((p) => _apply(answer, p));
            _finishAnswer(answer, turn, raw.toString(), stopReason);
          },
          cancelOnError: true,
        );
  }

  void _apply(ClaudeAnswer answer, ReplyPiece piece) {
    switch (piece) {
      case ReplyText(:final text):
        answer._addText(text);
      case ReplyUi():
        final controller = this.controller;
        // genui's own parser turns the block into typed messages; a block it
        // cannot parse is reported to the controller, which is what sends the
        // model its mistake.
        Stream.value(
          piece.source,
        ).transform(const A2uiParserTransformer()).listen((event) {
          if (event is A2uiMessageEvent) {
            controller.handleMessage(event.message);
          }
        }, onError: (Object e, StackTrace s) => controller.reportError(e, s));
        piece.createdSurfaces.forEach(answer._addSurface);
    }
  }

  void _finishAnswer(
    ClaudeAnswer answer,
    ClaudeTurn turn,
    String raw,
    String stopReason,
  ) {
    _stream = null;
    _current = null;
    if (stopReason == 'refusal') {
      // Whatever streamed before a mid-answer decline is discarded from the
      // history — it is not a complete answer — and the question with it, so
      // the turns still alternate.
      _history.removeLast();
      answer._finish(
        ClaudeAnswerState.refused,
        error: 'Claude declined to answer this.',
      );
    } else {
      _history.add(ClaudeTurn.assistant(raw.isEmpty ? '(no answer)' : raw));
      answer._finish(
        stopReason == 'max_tokens'
            ? ClaudeAnswerState.truncated
            : ClaudeAnswerState.done,
      );
    }
    notifyListeners();
    _flushInteractions();
  }

  void _fail(
    ClaudeAnswer answer,
    ClaudeTurn turn,
    String message, {
    bool retryable = false,
    bool needsAccount = false,
  }) {
    _stream = null;
    _current = null;
    _history.removeLast();
    _failedTurn = turn;
    answer._finish(
      ClaudeAnswerState.failed,
      error: message,
      retryable: retryable,
      needsAccount: needsAccount,
    );
    notifyListeners();
  }

  // --- the loop back from generated UI -------------------------------------

  void _onSubmit(ChatMessage message) {
    final interactions = [
      for (final part in message.parts.uiInteractionParts) part.interaction,
    ];
    if (interactions.isEmpty) return;
    _pendingInteractions.addAll(interactions);
    if (!busy) _flushInteractions();
  }

  void _flushInteractions() {
    if (_pendingInteractions.isEmpty || busy) return;
    final batch = List.of(_pendingInteractions);
    _pendingInteractions.clear();
    final actions = batch.map(claudeInteractionLabel).nonNulls.toList();
    if (actions.isEmpty) {
      // Only errors: the model's own UI failed to validate or run.
      if (_repairing) return;
      _repairing = true;
    } else {
      _repairing = false;
      _items.add(ClaudeQuestion(actions.join(', '), fromUi: true));
    }
    unawaited(_send(ClaudeTurn.user(claudeInteractionTurn(batch))));
  }

  @override
  void dispose() {
    _stream?.cancel();
    _submissions?.cancel();
    _controller?.dispose();
    super.dispose();
  }
}

/// The system prompt's own part, ahead of genui's catalogue and schema.
String claudePersona({required bool generateUi}) {
  final lines = [
    'You are Claude, built into Moonswing, the desktop shell of the user\'s '
        'Linux computer. You are answering from a small popup opened from the '
        'panel, so most questions are quick ones: answer directly and '
        'concisely.',
    'The popup shows plain text. Do not use Markdown headings, tables, bold or '
        'italics; a fenced code block is fine when the answer is code or a '
        'command.',
    'You cannot see the screen or act on the computer. When the user asks for '
        'something only they can do, tell them how.',
  ];
  if (generateUi) {
    lines.add(
      'IMPORTANT: Only generate a UI when the user asks for one, or when the '
      'task is genuinely interactive — a form to fill in, options to choose '
      'between, a checklist, a converter or calculator with inputs. A plain '
      'question gets a plain text answer and no UI at all. When you do build '
      'one, say what it is in one short sentence first, then output the A2UI '
      'messages.',
    );
  }
  return lines.join('\n');
}

/// The user turn that tells Claude what was done in its UI.
String claudeInteractionTurn(List<String> interactions) {
  final blocks = interactions.map((i) => '```json\n$i\n```').join('\n');
  return 'The user interacted with the generated UI:\n$blocks';
}

/// What the conversation shows for one interaction: the action's name, or
/// null when it is an error report rather than something the user did.
String? claudeInteractionLabel(String interaction) {
  try {
    final decoded = jsonDecode(interaction);
    if (decoded is! Map) return null;
    final action = decoded['action'];
    if (action is Map && action['name'] is String) {
      return (action['name'] as String).replaceAll('_', ' ');
    }
  } on FormatException {
    // Not JSON: not something to label.
  }
  return null;
}
