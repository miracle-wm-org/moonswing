// `[modules.claude]`, beside the feature it configures, the shape
// `github_config.dart` has: the chat store reads it and the bar module
// re-exports it.

import 'package:moonswing/claude/claude_api.dart';
import 'package:moonswing/config_reader.dart';

/// The Claude module's options.
class ClaudeConfig {
  const ClaudeConfig({
    this.model = kClaudeDefaultModel,
    this.effort = kClaudeDefaultEffort,
    this.generateUi = true,
  });

  /// The model questions go to. Free-typed: the list of models moves faster
  /// than the shell does, and the API's own error names a model it will not
  /// serve.
  final String model;

  /// How hard the model thinks before answering — one of [kClaudeEfforts].
  final String effort;

  /// Whether Claude is offered genui's catalogue, and so may answer with a
  /// generated UI. Off, every answer is text, and the system prompt is a few
  /// lines rather than several thousand tokens of schema.
  final bool generateUi;

  static ClaudeConfig fromMap(Map<String, dynamic>? map) {
    if (map == null) return const ClaudeConfig();
    const defaults = ClaudeConfig();
    final effort = map.stringOrNull('effort');
    return ClaudeConfig(
      model: map.stringOrNull('model') ?? defaults.model,
      // An effort the API does not know costs the key, not the request: it
      // would be a 400 on every question.
      effort: kClaudeEfforts.contains(effort) ? effort! : defaults.effort,
      generateUi: map.boolOr('generate_ui', defaults.generateUi),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClaudeConfig &&
          other.model == model &&
          other.effort == effort &&
          other.generateUi == generateUi;

  @override
  int get hashCode => Object.hash(model, effort, generateUi);
}
