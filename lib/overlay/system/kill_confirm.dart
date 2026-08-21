import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/system/models.dart';
import 'package:graceful_shell/system/process_killer.dart';

/// Whether the user is being asked to terminate a process politely, or to kill
/// one that has already ignored a SIGTERM.
enum KillSeverity { terminate, force }

/// The confirmation card, shown over the process table.
///
/// A scrim plus a [PopupCard] rather than a Material dialog, which the shell
/// does not use anywhere. The one thing it does not take from the theme is its
/// rim: the accent border marks a destructive action, so it overrides
/// `popup_border` rather than following it.
class KillConfirm extends StatelessWidget {
  const KillConfirm({
    super.key,
    required this.process,
    required this.severity,
    required this.onCancel,
    required this.onConfirm,
  });

  final ProcessRow process;
  final KillSeverity severity;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final isForce = severity == KillSeverity.force;

    return Stack(
      children: [
        // Tapping the scrim cancels, which is the least surprising thing a
        // click outside a confirmation can do.
        Positioned.fill(
          child: GestureDetector(
            onTap: onCancel,
            child: Container(color: const Color(0x99000000)),
          ),
        ),
        Center(
          child: SizedBox(
            width: 380,
            child: PopupCard(
              // The accent rim is what marks a destructive action, so it
              // overrides the theme's popup_border rather than following it.
              border: Border.all(color: theme.accent, width: 1.5),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isForce ? 'Force quit ${process.name}?' : 'Quit ${process.name}?',
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: theme.fontFamily,
                      fontWeight: FontWeight.w600,
                      color: theme.popupForeground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isForce
                        // Spelling out the consequence, because this is the path
                        // that loses an editor's unsaved buffer.
                        ? 'PID ${process.pid} ignored the request to quit. Forcing it '
                            'will end it immediately, without giving it a chance to '
                            'save.'
                        : 'PID ${process.pid} will be asked to shut down.',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: theme.fontFamily,
                      height: 1.4,
                      color: theme.popupForeground.withValues(alpha: 0.7),
                    ),
                  ),
                  if (process.cmdline.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.controlSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        process.cmdline,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SettingsOptionButton(
                        label: 'Cancel',
                        selected: false,
                        onTap: onCancel,
                      ),
                      const SizedBox(width: 8),
                      SettingsOptionButton(
                        label: isForce ? 'Force quit' : 'Quit',
                        selected: true,
                        onTap: onConfirm,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The strip that explains a kill that did not happen.
///
/// [KillOutcome.signalled] needs no banner — the row simply disappears on the
/// next poll. The others are all cases where nothing happened, and a row that
/// just sits there unchanged reads as a bug.
class KillBanner extends StatelessWidget {
  const KillBanner({
    super.key,
    required this.outcome,
    required this.processName,
    required this.pid,
    required this.onDismiss,
  });

  final KillOutcome outcome;
  final String processName;
  final int pid;
  final VoidCallback onDismiss;

  static String messageFor(KillOutcome outcome, String name, int pid) {
    switch (outcome) {
      case KillOutcome.permissionDenied:
        return 'Could not quit $name (PID $pid): permission denied. It belongs '
            'to another user.';
      case KillOutcome.pidReused:
        return '$name (PID $pid) had already exited, and the PID now belongs to '
            'a different process. Nothing was signalled.';
      case KillOutcome.refused:
        return '$name (PID $pid) cannot be killed from here — it is the shell '
            'itself or the init process.';
      case KillOutcome.alreadyGone:
        return '$name (PID $pid) had already exited.';
      case KillOutcome.signalled:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.accent.withValues(alpha: 0.18),
      child: Row(
        children: [
          Expanded(
            child: Text(
              messageFor(outcome, processName, pid),
              style: TextStyle(
                fontSize: 12,
                fontFamily: theme.fontFamily,
                color: theme.popupForeground.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SettingsIconButton(
            icon: FontAwesomeIcons.xmark,
            size: 11,
            onTap: onDismiss,
          ),
        ],
      ),
    );
  }
}
