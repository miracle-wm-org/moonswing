// The application launcher: a centred search card over a blurred backdrop, in its
// own full-screen layer-shell window.
//
// Everything it acts on is injected — the app list and the two launch callbacks —
// so widget tests drive it without touching GIO or spawning applications.


import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/app_info.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/launcher/app_search.dart';
import 'package:moonswing/launcher/expression.dart';
import 'package:moonswing/launcher/unit_convert.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay_fade_scaffold.dart';
import 'package:moonswing/overlay_search_field.dart';
import 'package:moonswing/scopes.dart';

/// Width of the card. Fixed: the rows need a bounded width, and a launcher that
/// resizes as you type is unusable.
const double kLauncherCardWidth = 640;

/// Height of the results area. Fixed, not a maximum: the card must not resize
/// on every keystroke, and an empty result set must not let it grow.
const double kLauncherListHeight = 420;

/// Row height. Fixed so the actions flyout can be positioned arithmetically
/// against the scroll offset, with no LayerLink or Overlay involved.
const double kLauncherRowHeight = 44;

/// The launcher card and its backdrop.
///
/// Follows [SettingsOverlay]'s close handshake: the owner flips [closingNotifier],
/// this plays its exit animation, then calls [onClosed].
class LauncherOverlay extends StatefulWidget {
  const LauncherOverlay({
    super.key,
    required this.closingNotifier,
    required this.onClosed,
    required this.apps,
    required this.onLaunch,
    this.onLaunchAction,
    this.loading = false,
  });

  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  /// The searchable index to rank against.
  final List<SearchableApp> apps;

  /// Whether [apps] is still being built. The index is enumerated after the
  /// shell's first frame, so the shortcut can beat it — and an empty list that
  /// means "not yet" must not read as "you have no applications".
  final bool loading;

  final void Function(AppEntry app) onLaunch;
  final void Function(AppEntry app, AppAction action)? onLaunchAction;

  @override
  State<LauncherOverlay> createState() => _LauncherOverlayState();
}

class _LauncherOverlayState extends State<LauncherOverlay> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'launcher-search');
  final _scrollController = ScrollController();

  String _query = '';
  List<AppEntry> _results = const [];
  String? _mathResult;
  UnitConversion? _unitResult;
  int _selected = 0;

  /// Index of the row whose actions flyout is open, or null.
  int? _flyoutRow;

  @override
  void initState() {
    super.initState();
    _results = rankApps(widget.apps, '');
  }

  /// Re-ranks when the index lands under an already-open launcher — the root
  /// rebuilds this widget with the finished list, and the user is by then
  /// probably part-way through a query, so the current one is re-applied rather
  /// than reset.
  @override
  void didUpdateWidget(LauncherOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.apps, oldWidget.apps)) {
      setState(() {
        _results = rankApps(widget.apps, _query);
        _selected = 0;
        _flyoutRow = null;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _requestClose() {
    widget.closingNotifier.value = true;
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _results = rankApps(widget.apps, value);
      _mathResult = evaluateExpression(value);
      _unitResult = convertQuery(value);
      _selected = 0;
      _flyoutRow = null;
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _launchSelected() {
    if (_selected < 0 || _selected >= _results.length) return;
    widget.onLaunch(_results[_selected]);
    // Close without the exit animation: the window holds keyboard focus, and
    // fading it out for a fifth of a second is long enough for the shell to win
    // the focus race against the application that is starting up.
    widget.onClosed();
  }

  void _launchAction(AppEntry app, AppAction action) {
    widget.onLaunchAction?.call(app, action);
    widget.onClosed();
  }

  void _moveSelection(int delta) {
    if (_results.isEmpty) return;
    setState(() {
      _selected = (_selected + delta).clamp(0, _results.length - 1);
      _flyoutRow = null;
    });
    _scrollSelectedIntoView();
  }

  void _scrollSelectedIntoView() {
    if (!_scrollController.hasClients) return;
    final top = _selected * kLauncherRowHeight;
    final bottom = top + kLauncherRowHeight;
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    if (top < offset) {
      _scrollController.jumpTo(top);
    } else if (bottom > offset + viewport) {
      _scrollController.jumpTo(bottom - viewport);
    }
  }

  void _toggleFlyout(int row) {
    if (_results[row].actions.isEmpty) return;
    setState(() {
      _flyoutRow = _flyoutRow == row ? null : row;
      _selected = row;
    });
  }

  /// True when the caret sits at the very end of the query with nothing
  /// selected — the only time Right can mean "open this row's actions" without
  /// stealing the key from the text field.
  bool get _caretAtEnd {
    final selection = _searchController.selection;
    return selection.isCollapsed &&
        selection.baseOffset == _searchController.text.length;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        // One press dismisses — a launcher opened by accident should not need
        // three. The exception is an open flyout, which is what Escape closes
        // first if there is one.
        if (_flyoutRow != null) {
          setState(() => _flyoutRow = null);
        } else {
          _requestClose();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _launchSelected();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (!_caretAtEnd || _selected >= _results.length) {
          return KeyEventResult.ignored; // let the caret move
        }
        if (_results[_selected].actions.isEmpty) return KeyEventResult.ignored;
        _toggleFlyout(_selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        if (_flyoutRow == null) return KeyEventResult.ignored;
        setState(() => _flyoutRow = null);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      // No WidgetsApp is mounted, so the default text-editing key bindings have
      // to be supplied by hand. Focus must nest *inside* them: key events
      // propagate upwards from the focused node, so the lower handler is the
      // one that gets first refusal on Up/Down/Enter/Escape.
      child: DefaultTextEditingShortcuts(
        child: DefaultTextStyle(
          style: TextStyle(
            fontFamily: theme.fontFamily,
            fontSize: 14,
            color: theme.popupForeground,
          ),
          child: Focus(
            onKeyEvent: _onKey,
            // The shell has no input-region support, so this surface swallows
            // every click on the monitor — including on the bar button that
            // opened it. Without dismiss-on-backdrop a mouse-only user would
            // have no way out.
            child: FadeOverlayScaffold(
              closing: widget.closingNotifier,
              onClosed: widget.onClosed,
              onBackdropTap: _requestClose,
              child: _buildCard(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(ThemeConfig theme) {
    return GestureDetector(
      // Absorb taps so clicking inside the card does not dismiss it.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: SizedBox(
        width: kLauncherCardWidth,
        child: Container(
          decoration: BoxDecoration(
            color: theme.popupBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.accent, width: 1.5),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OverlaySearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                theme: theme,
                hint: 'Search applications, a calculation, or a conversion…',
                onChanged: _onQueryChanged,
              ),
              if (_mathResult case final result?) ...[
                const SizedBox(height: 8),
                _MathResultRow(theme: theme, expression: _query, result: result),
              ],
              // Never both: a conversion carries no operator, and
              // `looksLikeExpression` refuses a query without one.
              if (_unitResult case final conversion?
                  when _mathResult == null) ...[
                const SizedBox(height: 8),
                _UnitResultRow(theme: theme, conversion: conversion),
              ],
              const SizedBox(height: 8),
              // Flexible, then a fixed height: the SizedBox pins the results
              // area to one size no matter how many rows there are, and the
              // Flexible caps it at whatever the surface can actually give
              // (which only bites on a very short monitor).
              Flexible(
                child: SizedBox(
                  height: kLauncherListHeight,
                  child: _buildResults(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeConfig theme) {
    if (_results.isEmpty) {
      if (widget.loading) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoadingIndicator(color: theme.muted, size: 18),
              const SizedBox(height: 12),
              Text(
                'Indexing applications…',
                style: TextStyle(color: theme.muted, fontSize: 13),
              ),
            ],
          ),
        );
      }
      return Center(
        child: Text(
          _query.isEmpty ? 'No applications' : 'No matching applications',
          style: TextStyle(color: theme.muted, fontSize: 13),
        ),
      );
    }

    // The flyout is a Stack child rather than an OverlayPortal: this window is
    // already full-screen and rows have a fixed extent, so its position is pure
    // arithmetic — and an Overlay's entries do not rebuild on setState, which
    // would be a trap for content that changes on every keystroke.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.zero,
          itemExtent: kLauncherRowHeight,
          itemCount: _results.length,
          itemBuilder: (context, i) {
            final app = _results[i];
            return _AppRow(
              theme: theme,
              app: app,
              selected: i == _selected,
              flyoutOpen: _flyoutRow == i,
              onTap: () {
                setState(() => _selected = i);
                _launchSelected();
              },
              onHover: () {
                if (_selected != i) setState(() => _selected = i);
              },
              onToggleActions: () => _toggleFlyout(i),
            );
          },
        ),
        if (_flyoutRow case final row?)
          _buildFlyout(theme, row, kLauncherListHeight),
      ],
    );
  }

  Widget _buildFlyout(ThemeConfig theme, int row, double listHeight) {
    final app = _results[row];
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    var top = row * kLauncherRowHeight - offset;
    // Keep the card on screen when the row it belongs to is near the bottom.
    final cardHeight = app.actions.length * 34.0 + 8;
    if (top + cardHeight > listHeight) {
      top = (listHeight - cardHeight).clamp(0.0, listHeight);
    }

    return Positioned(
      top: top,
      right: 8,
      child: _ActionsFlyout(
        theme: theme,
        actions: app.actions,
        onSelected: (action) => _launchAction(app, action),
      ),
    );
  }
}

/// The calculator row, shown above the app results when the query evaluates.
class _MathResultRow extends StatelessWidget {
  const _MathResultRow({
    required this.theme,
    required this.expression,
    required this.result,
  });

  final ThemeConfig theme;
  final String expression;
  final String result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accent, width: 1),
      ),
      child: Row(
        children: [
          FaIcon(FontAwesomeIcons.equals, size: 13, color: theme.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${expression.trim()} =',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.muted, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            result,
            style: TextStyle(
              color: theme.popupForeground,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The conversion row, shown above the app results when the query is a quantity —
/// `1kg`, `72f`, `5 km to mi`.
///
/// One shape for both forms the converter answers in: a query naming its target
/// unit produces a single value, a bare one up to [kUnitPeerLimit]. A `Wrap`
/// rather than a `Row`, because that is the difference between a fourth peer that
/// moves to a second line and one that overflows the card.
class _UnitResultRow extends StatelessWidget {
  const _UnitResultRow({required this.theme, required this.conversion});

  final ThemeConfig theme;
  final UnitConversion conversion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.controlSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.accent, width: 1),
      ),
      child: Row(
        children: [
          FaIcon(FontAwesomeIcons.rightLeft, size: 12, color: theme.muted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '${formatQuantity(conversion.input)} =',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.muted, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final result in conversion.results)
                  _ConvertedValue(theme: theme, quantity: result),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One converted quantity: the number carrying the emphasis, its unit beside it
/// in the muted tier — the same split the system monitor's stat tiles make, and
/// the reason a row of four of these still reads as four answers rather than as
/// a sentence.
class _ConvertedValue extends StatelessWidget {
  const _ConvertedValue({required this.theme, required this.quantity});

  final ThemeConfig theme;
  final Quantity quantity;

  @override
  Widget build(BuildContext context) {
    final value = formatQuantityValue(quantity.value);
    if (value == null) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: value,
          style: TextStyle(
            color: theme.popupForeground,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(
          text: ' ${quantity.unit.symbol}',
          style: TextStyle(color: theme.muted, fontSize: 13),
        ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// One application row: icon, name, generic name, and — when the entry declares
/// any — a chevron opening its alternative launch options.
class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.theme,
    required this.app,
    required this.selected,
    required this.flyoutOpen,
    required this.onTap,
    required this.onHover,
    required this.onToggleActions,
  });

  final ThemeConfig theme;
  final AppEntry app;
  final bool selected;
  final bool flyoutOpen;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback onToggleActions;

  @override
  Widget build(BuildContext context) {
    final hasActions = app.actions.isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? theme.surfaceHover : const Color(0x00000000),
            borderRadius: BorderRadius.circular(8),
          ),
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
                  style:
                      TextStyle(color: theme.popupForeground, fontSize: 14),
                ),
              ),
              if (app.genericName.isNotEmpty) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    app.genericName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: theme.muted, fontSize: 12),
                  ),
                ),
              ],
              if (hasActions)
                MouseRegion(
                  onEnter: (_) {
                    if (!flyoutOpen) onToggleActions();
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onToggleActions,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10),
                      child: FaIcon(
                        FontAwesomeIcons.chevronRight,
                        size: 11,
                        color: flyoutOpen ? theme.popupForeground : theme.muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card listing one application's `[Desktop Action …]` entries.
class _ActionsFlyout extends StatelessWidget {
  const _ActionsFlyout({
    required this.theme,
    required this.actions,
    required this.onSelected,
  });

  final ThemeConfig theme;
  final List<AppAction> actions;
  final void Function(AppAction) onSelected;

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: theme.popupBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.divider, width: 1),
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final action in actions)
              _ActionRow(
                theme: theme,
                action: action,
                onTap: () => onSelected(action),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.theme,
    required this.action,
    required this.onTap,
  });

  final ThemeConfig theme;
  final AppAction action;
  final VoidCallback onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovered ? theme.surfaceHover : const Color(0x00000000),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            widget.action.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.popupForeground, fontSize: 13),
          ),
        ),
      ),
    );
  }
}
