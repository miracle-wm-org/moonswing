// The keybind cheat sheet: every shortcut miracle currently has configured,
// drawn as key caps, centred over a scrim in its own full-screen layer-shell
// window.
//
// It reads nothing itself. [KeybindStore] owns the one `GET_KEYBINDS` round
// trip for the machine and its failure state, and `keybind_model.dart` owns
// every decision about what a binding *reads* as — so this file is the card,
// the caps and the two columns, and a widget test drives all three with no
// compositor behind it.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:miracle/miracle.dart' show KeybindsResult;

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/keybinds/keybind_model.dart';
import 'package:graceful_shell/keybinds/keybind_store.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/overlay_fade_scaffold.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_text_root.dart';
import 'package:graceful_shell/theme/theme_config.dart';
import 'package:graceful_shell/theme/tokens.dart';

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
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// The store this leases. Defaults to the singleton; a widget test passes its
  /// own, which is what keeps this testable with no IPC socket behind it.
  final KeybindStore? store;

  @override
  State<KeybindCheatsheetOverlay> createState() =>
      _KeybindCheatsheetOverlayState();
}

class _KeybindCheatsheetOverlayState extends State<KeybindCheatsheetOverlay> {
  late final KeybindStore _store = widget.store ?? KeybindStore.instance;

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
    super.dispose();
  }

  /// Escape, and the backdrop: play the exit and go.
  void _requestClose() => widget.closingNotifier.value = true;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // Escape is the only key this window takes. Everything else — including the
    // scroll keys the list itself handles — belongs below.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
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
        Flexible(child: _buildBody(theme, result)),
      ],
    );
  }

  Widget _buildBody(ThemeConfig theme, KeybindsResult? result) {
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

    // The mark a scroll leaves travels to the nearest boundary, and without
    // this one that is the window — so every scrolled frame would re-record the
    // header and the full-output scrim as well as the rows.
    return RepaintBoundary(
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns =
                constraints.maxWidth >= kCheatsheetTwoColumnWidth;
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
        ),
      ),
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
            FaIcon(FontAwesomeIcons.keyboard, size: 18, color: theme.accent),
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
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              FaIcon(
                _sectionIcon(group.section),
                size: 11,
                color: theme.accent,
              ),
              const SizedBox(width: 8),
              Text(
                group.section.label.toUpperCase(),
                style: TextStyle(
                  fontSize: ShellFontSizes.caption,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: theme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: theme.divider),
          const SizedBox(height: 6),
          for (final row in group.rows) _KeybindRowTile(row: row),
        ],
      ),
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
