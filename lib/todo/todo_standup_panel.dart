// The card the board's standup button opens: the summary `todo_standup.dart`
// wrote, and a button to copy it for pasting into a chat.

import 'package:flutter/widgets.dart';

import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The standup card's width.
const double kTodoStandupPanelWidth = 560;

/// The standup card over a scrim that covers the board.
class TodoStandupLayer extends StatelessWidget {
  const TodoStandupLayer({
    super.key,
    required this.report,
    required this.onDone,
    this.copy = copyTextToClipboard,
  });

  final String report;
  final VoidCallback onDone;

  /// How "Copy" copies; a test records instead of forking `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return GestureDetector(
      // Absorbs clicks meant for the board underneath.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: theme.scrim,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kTodoStandupPanelWidth.clamp(
                  0,
                  (constraints.maxWidth - 32).clamp(0, double.infinity),
                ),
                maxHeight: (constraints.maxHeight - 32).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: _StandupCard(report: report, onDone: onDone, copy: copy),
            ),
          ),
        ),
      ),
    );
  }
}

class _StandupCard extends StatefulWidget {
  const _StandupCard({
    required this.report,
    required this.onDone,
    required this.copy,
  });

  final String report;
  final VoidCallback onDone;
  final Future<ClipboardResult> Function(String text) copy;

  @override
  State<_StandupCard> createState() => _StandupCardState();
}

class _StandupCardState extends State<_StandupCard> {
  String? _message;
  bool _messageIsError = false;

  Future<void> _copy() async {
    final result = await widget.copy(widget.report);
    if (!mounted) return;
    setState(() {
      _message = switch (result) {
        ClipboardResult.copied => 'The summary is on the clipboard.',
        ClipboardResult.unavailable => 'Install $kClipboardPackage to copy it.',
        ClipboardResult.failed => '$kClipboardCommand could not copy it.',
      };
      _messageIsError = result != ClipboardResult.copied;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(
        color: opaquePopupFill(theme),
        borderRadius: BorderRadius.circular(ShellRadii.card),
        border: Border.all(color: theme.accent),
        boxShadow: [BoxShadow(color: theme.popupShadowColor, blurRadius: 24)],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Standup',
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
                    fontWeight: FontWeight.w600,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: SettingsActionButton(label: 'Copy', onTap: _copy),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: SettingsActionButton(
                  label: 'Done',
                  primary: true,
                  onTap: widget.onDone,
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Text(
              _message!,
              style: TextStyle(
                fontSize: ShellFontSizes.secondary,
                color: _messageIsError ? kErrorColor : theme.accentText,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Flexible(
            child: Container(
              decoration: BoxDecoration(
                color: theme.popupBackground,
                borderRadius: BorderRadius.circular(ShellRadii.control),
                border: Border.all(color: theme.divider),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Text(
                  widget.report,
                  style: TextStyle(
                    fontSize: ShellFontSizes.body,
                    height: 1.4,
                    color: theme.popupForeground,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
