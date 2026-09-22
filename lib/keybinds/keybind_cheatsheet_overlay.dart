// The keybind cheat sheet: every shortcut on this machine, drawn as key caps,
// centred over a scrim in its own full-screen layer-shell window.
//
// Two sources, and the sheet is careful about which is which. The compositor's
// bindings come from miracle over IPC and are *read only* here — they are
// miracle's own configuration, edited under Settings › Window Manager, and a
// sheet that let one be changed would be writing another program's file from
// the wrong end of the shell. The shell's own four — the launcher, settings and
// emoji shortcuts, and the power button — come out of the shell's `config.toml`
// and are therefore editable in place: click one and press the combination.
//
// It reads nothing itself. [KeybindStore] owns the one `GET_KEYBINDS` round
// trip for the machine and its failure state, [ShellKeybindStore] owns the
// shell's half and the writes back, and `keybind_model.dart` and
// `shell_keybinds.dart` own every decision about what a binding *reads* as — so
// this file is the card, the caps and the two columns, and a widget test drives
// all of them with no compositor behind it.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:miracle/miracle.dart' show KeybindsResult;

import 'package:moonswing/hover_region.dart';
import 'package:moonswing/input_trigger/keysym.dart';
import 'package:moonswing/keybinds/keybind_model.dart';
import 'package:moonswing/keybinds/keybind_store.dart';
import 'package:moonswing/keybinds/shell_keybind_store.dart';
import 'package:moonswing/keybinds/shell_keybinds.dart';
import 'package:moonswing/keybinds/shortcut_capture.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/shell_text_root.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// The widest the card is allowed to get.
///
/// Two columns of shortcuts and no more: a sheet stretched across a 4K output
/// puts a row's description and its caps a foot apart, which is the one thing a
/// glanceable sheet cannot afford.
const double kCheatsheetMaxWidth = 940;

/// Below this the card drops to a single column — a rotated or small display,
/// where two columns would be two ellipsised ones.
const double kCheatsheetTwoColumnWidth = 640;

/// The gap between the two columns.
const double kCheatsheetColumnGap = 28;

/// One key cap's height, and the floor for its width so `A` and `Esc` sit on
/// the same baseline as a row of equal-height keys.
const double kKeyCapHeight = 22;

/// The keybind cheat sheet and its backdrop.
///
/// Follows the [FadeOverlayScaffold] close handshake: the owner flips
/// [closingNotifier], this plays its exit animation, then calls [onClosed].
class KeybindCheatsheetOverlay extends StatefulWidget {
  const KeybindCheatsheetOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    this.store,
    this.shellStore,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// The store this leases. Defaults to the singleton; a widget test passes its
  /// own, which is what keeps this testable with no IPC socket behind it.
  final KeybindStore? store;

  /// The shell's own shortcuts, and the writes back. Defaults to the singleton;
  /// a test passes one over a temporary config file, or none at all — an
  /// unbound store draws its four rows and offers no editing, which is also
  /// what a shell whose config could not be loaded shows.
  final ShellKeybindStore? shellStore;

  @override
  State<KeybindCheatsheetOverlay> createState() =>
      _KeybindCheatsheetOverlayState();
}

class _KeybindCheatsheetOverlayState extends State<KeybindCheatsheetOverlay> {
  late final KeybindStore _store = widget.store ?? KeybindStore.instance;
  late final ShellKeybindStore _shellStore =
      widget.shellStore ?? ShellKeybindStore.instance;

  /// Which shell shortcut is listening for a key press, or null.
  ///
  /// One notifier for the sheet rather than a `setState` on the card: a row
  /// entering capture must repaint that row and the one leaving it, not fifty
  /// rows that each measure their own description as they build.
  final ValueNotifier<ShellShortcut?> _capturing = ValueNotifier(null);

  /// The sheet's own focus, held rather than left implicit: a row that has
  /// finished capturing has to hand the keyboard *back*, or the Escape that
  /// closes the sheet would land on a node that no longer exists.
  final FocusNode _sheetFocus = FocusNode(debugLabel: 'keybind cheat sheet');

  @override
  void initState() {
    super.initState();
    // The lease *is* the request: the first one refreshes, so the sheet always
    // shows what the compositor is applying now rather than what it applied
    // before the last `reload_config`.
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    _capturing.dispose();
    _sheetFocus.dispose();
    super.dispose();
  }

  /// Escape, and the backdrop: play the exit and go.
  void _requestClose() => widget.closingNotifier.value = true;

  /// Takes the keyboard back from a row that has stopped capturing.
  void _restoreFocus() {
    if (!mounted) return;
    _sheetFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Escape is the only key this window takes. Everything else — including the
    // scroll keys the list itself handles — belongs below.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      // A row listening for a press owns Escape and answers it itself. This is
      // the case where the row lost the keyboard without finishing — Escape
      // then means "stop listening", not "close the sheet", or the user's way
      // out of a capture would be to close the whole sheet.
      if (_capturing.value != null) {
        _capturing.value = null;
        return KeyEventResult.handled;
      }
      _requestClose();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    // Its own text root, like the launcher and the power menu: the window
    // chrome supplies one, but a widget test pumping this alone must not have
    // to, and `Directionality.of` is a null-assert in release too.
    return ShellTextRoot(
      style: TextStyle(
        fontSize: ShellFontSizes.body,
        color: theme.popupForeground,
        decoration: TextDecoration.none,
        fontWeight: FontWeight.normal,
      ),
      child: Focus(
        focusNode: _sheetFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: FadeOverlayScaffold(
          closing: widget.closingNotifier,
          onClosed: widget.onClosed,
          // The shell has no input-region support, so this surface swallows
          // every click on the monitor; without dismiss-on-backdrop a
          // mouse-only user would have no way out.
          onBackdropTap: _requestClose,
          child: Padding(
            // Never flush against the edges of a small output; what is outside
            // this is backdrop, so a click there still dismisses.
            padding: const EdgeInsets.all(32),
            child: GestureDetector(
              // The card is not the backdrop: a click that lands between two
              // rows must not close the sheet.
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kCheatsheetMaxWidth,
                ),
                child: PopupCard(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                  child: ListenableBuilder(
                    listenable: _store,
                    builder: (context, _) => _buildCard(theme),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(ThemeConfig theme) {
    final result = _store.result;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CheatsheetHeader(
          actionKey: result == null ? null : primaryModifierLabel(result),
          refreshing: _store.refreshing && result != null,
        ),
        const SizedBox(height: 14),
        // A failure over a list the store already has: the last good sheet
        // stays readable and the reason sits above it, `KeyboardStore`'s rule.
        if (_store.error.isNotEmpty && result != null) ...[
          _CheatsheetError(
            message: _store.error,
            busy: _store.refreshing,
            onRetry: _store.retry,
          ),
          const SizedBox(height: 14),
        ],
        // One scroll view over both halves. The shell's shortcuts lead and are
        // full width: they are a handful of rows, they are the ones that can
        // be changed, and dealing them into the balanced columns below would
        // let the editor's own width decide how the compositor's fifty are
        // laid out.
        //
        // The boundary is here rather than around the columns for the reason it
        // was always there: the mark a scroll leaves travels to the nearest
        // one, and without it that is the window — so every scrolled frame
        // re-records the header and the full-output scrim as well as the rows.
        Flexible(
          child: RepaintBoundary(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListenableBuilder(
                    listenable: _shellStore,
                    builder: (context, _) => _ShellSectionBlock(
                      store: _shellStore,
                      compositor: result,
                      capturing: _capturing,
                      onCaptureEnd: _restoreFocus,
                    ),
                  ),
                  _buildCompositorBody(theme, result),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The compositor's half: its own bindings, grouped, and read only.
  Widget _buildCompositorBody(ThemeConfig theme, KeybindsResult? result) {
    if (result == null) {
      if (_store.status == KeybindStatus.loading) {
        return const SizedBox(
          height: 120,
          child: Center(child: LoadingIndicator(size: 22)),
        );
      }
      if (_store.error.isNotEmpty) {
        return _CheatsheetError(
          message: _store.error,
          busy: _store.refreshing,
          onRetry: _store.retry,
        );
      }
      return const SizedBox(height: 80);
    }

    final groups = groupKeybinds(result);
    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Miracle has no key bindings configured.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.muted),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Said once, above the compositor's sections: the sheet now carries two
        // kinds of row and only one of them answers a click, so the rows that
        // do not have to say where they *are* changed.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "The window manager's own bindings. Change these under "
            'Settings › Window Manager › Key Bindings.',
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              color: theme.muted,
            ),
          ),
        ),
        _buildGroups(groups),
      ],
    );
  }

  /// The compositor's sections, in one column or two.
  Widget _buildGroups(List<KeybindGroup> groups) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= kCheatsheetTwoColumnWidth;
        if (!twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in groups) _SectionBlock(group: group),
            ],
          );
        }
        final columns = balanceGroups(groups);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, column) in columns.indexed) ...[
              if (index > 0) const SizedBox(width: kCheatsheetColumnGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final group in column) _SectionBlock(group: group),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The title row, and what the Action Key resolves to on this machine.
class _CheatsheetHeader extends StatelessWidget {
  const _CheatsheetHeader({required this.actionKey, required this.refreshing});

  /// The key `Modifier.primary` stands in for, e.g. `Super`, or null when
  /// miracle reported one this shell cannot name.
  final String? actionKey;

  /// Whether a refresh is in flight over a sheet that is already on screen.
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            FaIcon(
              FontAwesomeIcons.keyboard,
              size: 18,
              color: theme.accentText,
            ),
            const SizedBox(width: 10),
            // Expanded rather than a Spacer after it: the title is the piece
            // that gives, so a narrow output ellipsises it instead of pushing
            // "Esc to close" off the card.
            Expanded(
              child: Text(
                'Keyboard shortcuts',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: ShellFontSizes.title,
                  fontWeight: FontWeight.w600,
                  color: theme.popupForeground,
                ),
              ),
            ),
            if (refreshing) ...[
              const LoadingIndicator(size: 12),
              const SizedBox(width: 10),
            ],
            Text(
              'Esc to close',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.muted,
              ),
            ),
          ],
        ),
        // Said once, on its own line, rather than fifty times down the rows:
        // every row carries the key the Action Key resolved *to*, so this is
        // the line that connects miracle's own word for it to the caps below.
        if (actionKey case final key?) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Action Key',
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: theme.muted,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '=',
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  color: theme.muted,
                ),
              ),
              const SizedBox(width: 6),
              KeyCapChip(cap: KeyCap(key)),
            ],
          ),
        ],
      ],
    );
  }
}

/// One section: its heading, then its rows.
class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.group});

  final KeybindGroup group;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeading(
          icon: _sectionIcon(group.section),
          label: group.section.label,
        ),
        for (final row in group.rows) _KeybindRowTile(row: row),
      ],
    ),
  );
}

/// A section's heading and its rule.
///
/// Shared by the compositor's sections and the shell's own, because the sheet
/// is one sheet: two headings drawn by two widgets are two headings that drift.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.label});

  final FaIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            FaIcon(icon, size: 11, color: theme.accentText),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.accentText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: theme.divider),
        const SizedBox(height: 6),
      ],
    );
  }
}

/// The picture a section is headed with.
///
/// In the widget rather than on [KeybindSection] so the model stays
/// Flutter-free — `miracle_labels.dart`'s rule.
FaIconData _sectionIcon(KeybindSection section) => switch (section) {
  KeybindSection.windows => FontAwesomeIcons.windowMaximize,
  KeybindSection.layout => FontAwesomeIcons.tableColumns,
  KeybindSection.workspaces => FontAwesomeIcons.borderAll,
  KeybindSection.magnifier => FontAwesomeIcons.magnifyingGlass,
  KeybindSection.session => FontAwesomeIcons.powerOff,
  KeybindSection.commands => FontAwesomeIcons.terminal,
  KeybindSection.other => FontAwesomeIcons.puzzlePiece,
};

/// One shortcut: what it does on the left, the caps to press on the right.
class _KeybindRowTile extends StatelessWidget {
  const _KeybindRowTile({required this.row});

  final KeybindRow row;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.secondary,
                    color: theme.popupForeground,
                    // A shell command is set in the monospace it was typed in,
                    // so `$HOME/bin/x -y` does not read as prose.
                    fontFamily: row.isCommand ? 'monospace' : null,
                  ),
                ),
                if (row.detail case final detail?)
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: theme.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Not a [Wrap]: the caps keep one line and the description ellipsises
          // instead, so a narrow column never reflows a shortcut onto two rows
          // that read as two shortcuts.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, cap) in row.caps.indexed) ...[
                if (index > 0) const _CapJoiner(),
                KeyCapChip(cap: cap),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The shell's own shortcuts, and the only rows on this sheet that can be
/// changed from it.
///
/// Full width and first, rather than dealt into [balanceGroups]' columns: they
/// are four rows against the compositor's fifty, they are the interactive ones,
/// and a row that grows while it listens for a key press must not be able to
/// re-deal the sheet around it.
class _ShellSectionBlock extends StatelessWidget {
  const _ShellSectionBlock({
    required this.store,
    required this.compositor,
    required this.capturing,
    required this.onCaptureEnd,
  });

  final ShellKeybindStore store;

  /// The compositor's bindings, for the collision warning — a shell shortcut on
  /// a combination miracle also uses is worth saying out loud, and only this
  /// half of the sheet knows both.
  final KeybindsResult? compositor;

  final ValueNotifier<ShellShortcut?> capturing;
  final VoidCallback onCaptureEnd;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SectionHeading(
            icon: FontAwesomeIcons.sliders,
            label: kShellSectionLabel,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              store.canEdit
                  ? 'The shell registers these itself. Click one and press the '
                        'combination you want.'
                  : 'The shell registers these itself, from [shortcuts] in its '
                        'config.toml.',
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                color: theme.muted,
              ),
            ),
          ),
          // Said once, over every row, rather than per row: a global
          // shortcut is registered on the compositor's first answer and latches
          // there, so *every* edit here is a change to what the next run binds.
          if (store.needsRestart)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.rotateRight,
                    size: 10,
                    color: theme.accentText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Restart the shell to apply your changes — global '
                      'shortcuts are registered once, at start-up.',
                      style: TextStyle(
                        fontSize: ShellFontSizes.caption,
                        color: theme.accentText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final shortcut in ShellShortcut.values)
            _ShellShortcutTile(
              shortcut: shortcut,
              store: store,
              compositor: compositor,
              capturing: capturing,
              onCaptureEnd: onCaptureEnd,
            ),
        ],
      ),
    );
  }
}

/// One of the shell's shortcuts: what it does, what it is on, and — while it is
/// listening — the next combination the user presses.
class _ShellShortcutTile extends StatefulWidget {
  const _ShellShortcutTile({
    required this.shortcut,
    required this.store,
    required this.compositor,
    required this.capturing,
    required this.onCaptureEnd,
  });

  final ShellShortcut shortcut;
  final ShellKeybindStore store;
  final KeybindsResult? compositor;
  final ValueNotifier<ShellShortcut?> capturing;
  final VoidCallback onCaptureEnd;

  @override
  State<_ShellShortcutTile> createState() => _ShellShortcutTileState();
}

class _ShellShortcutTileState extends State<_ShellShortcutTile> {
  /// Present whether or not this row is listening, so that starting a capture
  /// is a `requestFocus` on a node that is already in the tree rather than a
  /// rebuild that has to land before the first key arrives.
  final FocusNode _focus = FocusNode(debugLabel: 'shell shortcut');

  /// What the last press could not be used for, or what it collided with.
  String? _message;

  /// Whether [_message] is a warning about something that *was* applied rather
  /// than a reason nothing was.
  bool _warning = false;

  bool get _isCapturing => widget.capturing.value == widget.shortcut;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _startCapture() {
    if (!widget.store.canEdit) return;
    setState(() {
      _message = null;
      _warning = false;
    });
    widget.capturing.value = widget.shortcut;
    _focus.requestFocus();
  }

  /// Stops listening and hands the keyboard back to the sheet, so Escape closes
  /// it again.
  void _endCapture() {
    if (widget.capturing.value == widget.shortcut) {
      widget.capturing.value = null;
    }
    widget.onCaptureEnd();
  }

  void _cancelCapture() {
    setState(() {
      _message = null;
      _warning = false;
    });
    _endCapture();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_isCapturing) return KeyEventResult.ignored;
    // Every key belongs to the capture while it is running, the key *up* of the
    // press that ended it included: letting one through would reach the sheet's
    // own handler, which is the one that closes the window on Escape.
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _cancelCapture();
      return KeyEventResult.handled;
    }
    // Backspace clears the binding — the one thing a *combination* cannot say,
    // and the way back to a shortcut the user has switched off.
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      widget.store.disable(widget.shortcut);
      _cancelCapture();
      return KeyEventResult.handled;
    }
    // A modifier on its own is the user still on the way to a combination.
    if (isShortcutModifierKey(key)) return KeyEventResult.handled;

    final spec = captureShortcutFromKeyboard(key, HardwareKeyboard.instance);
    if (spec == null) {
      // Stays listening: the next press is the correction, and the user has to
      // be told what happened to this one or the row simply looks broken.
      setState(() {
        _message =
            'The shell has no name for that key. Bind it by hand in '
            'config.toml, with the 0x or code: form.';
        _warning = false;
      });
      return KeyEventResult.handled;
    }
    _apply(spec);
    return KeyEventResult.handled;
  }

  void _apply(ShortcutSpec spec) {
    final store = widget.store;
    final collision = shellCollisionFor(widget.shortcut, spec, store.shortcuts);
    if (collision != null) {
      // Refused, not warned about: two of the shell's shortcuts on one
      // combination is the *later* one silently never registering, which is
      // indistinguishable from a shortcut that does not work.
      setState(() {
        _message = '${shortcutLabel(spec)} is already "${collision.label}".';
        _warning = false;
      });
      return;
    }
    store.setShortcut(widget.shortcut, spec);
    // A collision with the compositor is only ever a warning: which of the two
    // registrations wins is miracle's business, and the sheet's job is to say
    // so before the user finds out by pressing it.
    final clash = compositorCollisionFor(spec, widget.compositor);
    setState(() {
      _message = clash == null
          ? null
          : 'The window manager also uses this for "$clash".';
      _warning = clash != null;
    });
    _endCapture();
  }

  void _restoreDefault() {
    setState(() {
      _message = null;
      _warning = false;
    });
    widget.store.restoreDefault(widget.shortcut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final store = widget.store;
    final shortcut = widget.shortcut;
    // A boundary per row: a hover fill, a row entering capture and a message
    // appearing are all this row's business, and without one each of them
    // re-records the whole card.
    return RepaintBoundary(
      child: Focus(
        focusNode: _focus,
        // Never a Tab stop: the sheet is read, and a traversal that could land
        // on a row would arm a capture nobody asked for.
        skipTraversal: true,
        canRequestFocus: store.canEdit,
        onKeyEvent: _onKey,
        child: ValueListenableBuilder<ShellShortcut?>(
          valueListenable: widget.capturing,
          builder: (context, capturing, _) {
            final isCapturing = capturing == shortcut;
            return HoverRegion(
              onTap: store.canEdit ? _startCapture : null,
              // A read-only row keeps the ordinary pointer: the hand is the
              // sheet's promise that a click does something.
              cursor: store.canEdit
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              builder: (context, hovered) => Container(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                decoration: BoxDecoration(
                  color: isCapturing
                      ? theme.accent.withValues(alpha: 0.12)
                      : (hovered && store.canEdit ? theme.surfaceHover : null),
                  borderRadius: BorderRadius.circular(ShellRadii.control),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _describe(theme, isCapturing)),
                        const SizedBox(width: 12),
                        _trailing(theme, isCapturing),
                        if (store.canEdit && !isCapturing) ...[
                          const SizedBox(width: 6),
                          _RowAction(
                            icon: FontAwesomeIcons.pen,
                            rowHovered: hovered,
                            onTap: _startCapture,
                          ),
                          // Only where there is something to go back to, so the
                          // row carries one affordance rather than two most of
                          // the time.
                          if (!store.isDefault(shortcut))
                            _RowAction(
                              icon: FontAwesomeIcons.arrowRotateLeft,
                              rowHovered: hovered,
                              onTap: _restoreDefault,
                            ),
                        ],
                      ],
                    ),
                    if (_message case final message?)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          message,
                          style: TextStyle(
                            fontSize: ShellFontSizes.caption,
                            color: _warning ? theme.muted : kErrorColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The left-hand column: what the shortcut does, and whatever qualifies it.
  Widget _describe(ThemeConfig theme, bool isCapturing) {
    final shortcut = widget.shortcut;
    final detail = isCapturing
        ? 'Press a combination — Esc cancels, Backspace clears it.'
        : (widget.store.isPending(shortcut)
              ? 'Takes effect when the shell restarts'
              : shortcut.detail);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          shortcut.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: ShellFontSizes.secondary,
            color: theme.popupForeground,
          ),
        ),
        if (detail != null)
          Text(
            detail,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              color: isCapturing ? theme.accentText : theme.muted,
            ),
          ),
      ],
    );
  }

  /// The right-hand end: the caps, the word for a shortcut that is switched
  /// off, or the prompt while the row is listening.
  Widget _trailing(ThemeConfig theme, bool isCapturing) {
    if (isCapturing) {
      return Container(
        height: kKeyCapHeight,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(ShellRadii.control),
          border: Border.all(color: theme.accent),
        ),
        child: Text(
          'Press keys…',
          style: TextStyle(
            fontSize: ShellFontSizes.caption,
            fontWeight: FontWeight.w600,
            color: theme.accentText,
          ),
        ),
      );
    }
    final spec = widget.store.specFor(widget.shortcut);
    if (spec == null) {
      return SizedBox(
        height: kKeyCapHeight,
        child: Center(
          child: Text(
            kShellShortcutDisabled,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              color: theme.muted,
            ),
          ),
        ),
      );
    }
    // Not a [Wrap], [_KeybindRowTile]'s reason: the caps keep one line and the
    // description ellipsises instead.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, cap) in capsForSpec(spec).indexed) ...[
          if (index > 0) const _CapJoiner(),
          KeyCapChip(cap: cap),
        ],
      ],
    );
  }
}

/// The pencil and the undo on an editable row.
///
/// Its own [HoverRegion] inside the row's, so the icon lights independently and
/// a click on it is the icon's rather than the row's — a nested recognizer wins
/// over the one above it, which is what keeps "put this back" from also meaning
/// "start listening".
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.rowHovered,
    required this.onTap,
  });

  final FaIconData icon;

  /// Whether the row is hovered. The affordance is drawn faintly until then:
  /// four rows each carrying two lit buttons is a sheet that reads as a form.
  final bool rowHovered;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        width: ShellSizes.iconButton,
        height: ShellSizes.iconButton,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.surfacePressed : null,
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        child: FaIcon(
          icon,
          size: 10,
          color: hovered || rowHovered ? theme.popupForeground : theme.muted,
        ),
      ),
    );
  }
}

/// The `+` between two caps.
class _CapJoiner extends StatelessWidget {
  const _CapJoiner();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Text(
      '+',
      style: TextStyle(
        fontSize: ShellFontSizes.caption,
        color: ThemeScope.of(context).muted,
      ),
    ),
  );
}

/// One key, drawn as a key.
///
/// Public because the header uses it to show what the Action Key resolves to,
/// and because it is what a widget test looks for.
class KeyCapChip extends StatelessWidget {
  const KeyCapChip({super.key, required this.cap});

  final KeyCap cap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final glyph = cap.glyph;
    return Container(
      constraints: const BoxConstraints(minWidth: kKeyCapHeight),
      height: kKeyCapHeight,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(ShellRadii.control),
        border: Border.all(color: theme.divider),
        // The key's edge: an unblurred offset shadow, which is what makes a cap
        // read as a cap. A thicker bottom border would be the obvious way to
        // draw it and is not available — `BoxDecoration` requires a uniform
        // border once a `borderRadius` is set.
        boxShadow: [BoxShadow(color: theme.divider, offset: const Offset(0, 2))],
      ),
      child: glyph == null
          ? Text(
              cap.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontWeight: FontWeight.w600,
                color: theme.popupForeground,
              ),
            )
          : FaIcon(
              _glyphIcon(glyph),
              size: 10,
              color: theme.popupForeground,
            ),
    );
  }
}

/// The picture on a cap that has one.
FaIconData _glyphIcon(KeyCapGlyph glyph) => switch (glyph) {
  KeyCapGlyph.up => FontAwesomeIcons.arrowUp,
  KeyCapGlyph.down => FontAwesomeIcons.arrowDown,
  KeyCapGlyph.left => FontAwesomeIcons.arrowLeft,
  KeyCapGlyph.right => FontAwesomeIcons.arrowRight,
  KeyCapGlyph.enter => FontAwesomeIcons.arrowTurnDown,
  KeyCapGlyph.backspace => FontAwesomeIcons.deleteLeft,
};

/// Why the sheet is empty, or out of date, and the way to ask again.
///
/// `_KeyboardErrorStrip`'s shape: the reason is rendered, the last good value
/// stays, and the retry is the user's — the shell cannot see miracle come back.
class _CheatsheetError extends StatelessWidget {
  const _CheatsheetError({
    required this.message,
    required this.busy,
    required this.onRetry,
  });

  final String message;
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      color: kErrorColor.withValues(alpha: 0.12),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: FaIcon(
                  FontAwesomeIcons.triangleExclamation,
                  size: 12,
                  color: kErrorColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Could not read the key bindings',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: theme.popupForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              height: 1.4,
              color: theme.popupForeground.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: busy
                ? const SizedBox(
                    height: ShellSizes.minTapTarget,
                    width: 64,
                    child: Center(
                      child: LoadingIndicator(size: 12, color: kErrorColor),
                    ),
                  )
                : HoverRegion(
                    onTap: onRetry,
                    builder: (context, hovered) => Container(
                      width: 64,
                      height: ShellSizes.minTapTarget,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hovered
                            ? kErrorColor.withValues(alpha: 0.18)
                            : null,
                        border: Border.all(
                          color: kErrorColor.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(ShellRadii.control),
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontSize: ShellFontSizes.secondary,
                          color: kErrorColor,
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
