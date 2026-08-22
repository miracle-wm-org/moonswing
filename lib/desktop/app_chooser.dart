import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:graceful_shell/app_info.dart';
import 'package:graceful_shell/launcher/app_search.dart';
import 'package:graceful_shell/search_list.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';

/// Width of the chooser card. Fixed, like the launcher's: a list that resized
/// as you type is unusable.
const double kAppChooserWidth = 520;

/// Height of the results area. Fixed, not a maximum, so the card does not grow
/// and shrink on every keystroke.
const double kAppChooserListHeight = 360;

/// Row height. Fixed so the keyboard scroll-into-view is arithmetic.
const double kAppChooserRowHeight = 44;

/// A searchable list of installed applications, each with its own icon.
///
/// This is what "Add application…" opens instead of a file picker: asking
/// someone to find `firefox.desktop` under `/usr/share/applications` is asking
/// them to know where their distribution puts things.
///
/// Takes its app list and callbacks as parameters, so widget tests never touch
/// GIO — the same shape `LauncherOverlay` uses. The chosen [AppEntry]'s
/// `filename` is what the desktop grid pins; an entry with none is not
/// offered, because there would be nothing to store.
class AppChooserCard extends StatefulWidget {
  const AppChooserCard({
    super.key,
    required this.apps,
    required this.onSelected,
    required this.onCancel,
    this.loading = false,
  });

  final List<SearchableApp> apps;
  final ValueChanged<AppEntry> onSelected;
  final VoidCallback onCancel;

  /// Whether [apps] is still being built — the index is enumerated after the
  /// shell's first frame, so an empty list may just mean "not yet".
  final bool loading;

  @override
  State<AppChooserCard> createState() => _AppChooserCardState();
}

class _AppChooserCardState extends State<AppChooserCard> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  late List<AppEntry> _results;
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    _results = _rank('');
  }

  /// Re-ranks when the index lands under an already-open chooser, keeping
  /// whatever the user has typed so far.
  @override
  void didUpdateWidget(AppChooserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.apps, oldWidget.apps)) {
      setState(() {
        _results = _rank(_query.text);
        _highlighted = 0;
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _fieldFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// An app with no `.desktop` path cannot be pinned — `DesktopItem.target` is
  /// a path — so it is filtered out rather than offered and then rejected.
  List<AppEntry> _rank(String query) =>
      rankApps(widget.apps, query).where((a) => a.filename.isNotEmpty).toList();

  void _onQueryChanged(String value) {
    setState(() {
      _results = _rank(value);
      _highlighted = 0;
    });
    _scrollToHighlighted();
  }

  void _move(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _highlighted = (_highlighted + delta).clamp(0, _results.length - 1);
    });
    _scrollToHighlighted();
  }

  void _scrollToHighlighted() {
    if (!_scroll.hasClients) return;
    final offset =
        revealRowOffset(_highlighted, kAppChooserRowHeight, _scroll.position);
    if (offset != null) _scroll.jumpTo(offset);
  }

  void _accept() {
    if (_highlighted < 0 || _highlighted >= _results.length) return;
    widget.onSelected(_results[_highlighted]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        widget.onCancel();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _accept();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Center(
      child: SizedBox(
        width: kAppChooserWidth,
        child: PopupCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Focus wraps the field so key events propagate up from it: the
              // lower handler gets first refusal, which is what lets Up/Down/
              // Enter/Escape win while the arrows still edit text.
              Focus(
                onKeyEvent: _onKey,
                child: _SearchField(
                  controller: _query,
                  focusNode: _fieldFocus,
                  hint: 'Search applications…',
                  onChanged: _onQueryChanged,
                  onSubmitted: (_) => _accept(),
                ),
              ),
              Container(height: 1, color: theme.divider),
              SizedBox(
                height: kAppChooserListHeight,
                child: _results.isEmpty
                    ? Center(
                        child: widget.loading
                            ? LoadingIndicator(color: theme.muted, size: 18)
                            : Text(
                                'No matching applications.',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: theme.fontFamily,
                                  color: theme.popupForeground
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: EdgeInsets.zero,
                        itemExtent: kAppChooserRowHeight,
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final app = _results[index];
                          return AppChooserRow(
                            app: app,
                            highlighted: index == _highlighted,
                            onTap: () => widget.onSelected(app),
                            onHover: () {
                              if (_highlighted != index) {
                                setState(() => _highlighted = index);
                              }
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One application row: its icon, its name, and its generic name if it has one.
class AppChooserRow extends StatelessWidget {
  const AppChooserRow({
    super.key,
    required this.app,
    required this.highlighted,
    required this.onTap,
    this.onHover,
  });

  final AppEntry app;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback? onHover;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover?.call(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          color: highlighted ? theme.surfaceHover : null,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: AppIconImage(
                  iconName: app.iconName,
                  name: app.name,
                  size: 24,
                  foreground: theme.popupForeground,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                  ),
                ),
              ),
              if (app.genericName.isNotEmpty) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    app.genericName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: theme.fontFamily,
                      color: theme.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The chooser's search box. A bare [EditableText] with a placeholder, in the
/// shell's idiom — there is no Material dependency to draw one for us.
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Stack(
        children: [
          if (widget.controller.text.isEmpty)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.hint,
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          EditableText(
            controller: widget.controller,
            focusNode: widget.focusNode,
            autofocus: true,
            maxLines: 1,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: TextStyle(
              fontSize: 15,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
            cursorColor: theme.accent,
            backgroundCursorColor: theme.muted,
            selectionColor: theme.accent.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

/// The full-screen chooser: a dismiss-on-backdrop scrim behind the card.
///
/// Backdrop dismissal is not optional. The shell has no input-region support,
/// so this surface swallows every click on the monitor — without it a
/// mouse-only user would have no way out.
class AppChooserOverlay extends StatelessWidget {
  const AppChooserOverlay({
    super.key,
    required this.apps,
    required this.onSelected,
    required this.onCancel,
    this.loading = false,
  });

  final List<SearchableApp> apps;
  final ValueChanged<AppEntry> onSelected;
  final VoidCallback onCancel;

  /// Passed through to [AppChooserCard] — see its `loading`.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Directionality(
      textDirection: TextDirection.ltr,
      // Without this the shell's lack of a WidgetsApp leaves the search box
      // with no Backspace, no arrows and no Ctrl+A — the trap `SettingsOverlay`
      // documents.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 14,
            color: theme.popupForeground,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onCancel,
                  child: ColoredBox(color: theme.scrim),
                ),
              ),
              AppChooserCard(
                apps: apps,
                loading: loading,
                onSelected: onSelected,
                onCancel: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the chooser inside the nearest root [Overlay], resolving to the chosen
/// application or null if it was dismissed.
///
/// For hosts that already have an Overlay — the settings pane. The desktop does
/// not: it is on the background layer, where a modal would be drawn under every
/// application window, so the root gives it a window of its own instead. Same
/// split as `showFilePicker` vs `FilePickerController`.
Future<AppEntry?> showAppChooser(
  BuildContext context, {
  required List<SearchableApp> apps,
  bool loading = false,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final completer = Completer<AppEntry?>();
  late OverlayEntry entry;

  void close(AppEntry? result) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (context) => AppChooserOverlay(
      apps: apps,
      loading: loading,
      onSelected: close,
      onCancel: () => close(null),
    ),
  );
  overlay.insert(entry);
  return completer.future;
}
