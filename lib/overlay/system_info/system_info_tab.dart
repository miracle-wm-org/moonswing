import 'package:flutter/widgets.dart';
import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/system/stat_tile.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/system/system_info.dart';
import 'package:moonswing/theme/tokens.dart';

/// The **System Info** overlay tab: a read-only summary of the machine's
/// hardware, its input devices, its software, and the desktop environment, with
/// a button that puts all of it on the clipboard as plain text.
///
/// The data is static for a session, so — unlike the live System monitor tab —
/// this reads once in [initState] and never polls, and holds no lease. Until the
/// read resolves, every value shows the em-dash placeholder and there is nothing
/// to copy.
class SystemInfoTab extends StatefulWidget {
  const SystemInfoTab({
    super.key,
    this.read = _readMachine,
    this.copy = copyTextToClipboard,
  });

  /// Reads the machine; a test hands in a fixed [SystemInfo] instead.
  final Future<SystemInfo> Function() read;

  /// How "Copy all" copies; a test records instead of forking `wl-copy`.
  final Future<ClipboardResult> Function(String text) copy;

  static Future<SystemInfo> _readMachine() => SystemInfoReader().read();

  @override
  State<SystemInfoTab> createState() => _SystemInfoTabState();
}

class _SystemInfoTabState extends State<SystemInfoTab> {
  SystemInfo _info = const SystemInfo();
  bool _loaded = false;

  /// What the last copy did, said beside the button that did it. Null until
  /// the first press.
  ClipboardResult? _copied;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await widget.read();
    if (!mounted) return;
    setState(() {
      _info = info;
      _loaded = true;
    });
  }

  Future<void> _copy() async {
    final result = await widget.copy(systemInfoPlainText(_info));
    if (mounted) setState(() => _copied = result);
  }

  /// Width of the label column in every pair on this page.
  ///
  /// One value for all four sections, rather than per-section intrinsics, so the
  /// values line up down the whole page. Sized for the longest label here.
  static const double _labelWidth = 150;

  /// One pair. The label column is spelled once, here, so no section can drift
  /// out of the shared column — and the em-dash placeholder for a field this
  /// machine did not report comes with it.
  static StatLine _row(SystemInfoRow row) => StatLine(
    label: row.label,
    labelWidth: _labelWidth,
    value: row.value ?? '—',
  );

  /// The copy button and, once pressed, what became of it. A copy that did not
  /// land says why — a missing helper names the *package* — rather than leaving
  /// the user to find an empty clipboard.
  Widget _copyBar(BuildContext context) {
    final theme = ThemeScope.of(context);
    final copied = _copied;
    final (message, error) = switch (copied) {
      null => (null, false),
      ClipboardResult.copied => ('Copied to the clipboard.', false),
      ClipboardResult.unavailable => (
        'Install $kClipboardPackage to copy it.',
        true,
      ),
      ClipboardResult.failed => ('$kClipboardCommand could not copy it.', true),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        children: [
          SettingsActionButton(
            label: 'Copy all',
            icon: ShellGlyph.copy,
            compact: true,
            enabled: _loaded,
            onTap: _copy,
          ),
          if (message != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: error
                      ? kErrorColor
                      : theme.popupForeground.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = systemInfoSections(_info);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      children: [
        _copyBar(context),
        for (final (index, section) in sections.indexed) ...[
          if (index > 0) const SizedBox(height: 24),
          SystemCard(
            title: section.title,
            children: [for (final row in section.rows) _row(row)],
          ),
        ],
      ],
    );
  }
}
