import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/overlay/system/overview_page.dart';
import 'package:graceful_shell/overlay/system/process_table.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/system/system_stats_store.dart';

enum _SubTab { overview, processes }

/// The System tab: the machine's hardware at a glance, and every process on it.
///
/// **The tab must be told when it is visible.** The overlay's [IndexedStack]
/// builds every tab once and keeps them all alive, so this widget's `State`
/// exists — and would happily keep polling — while the user sits on Calendar or
/// Settings. [active] is what gates that: the detail lease, and with it the
/// per-process `/proc` walk, is held only while this is the selected tab.
class SystemTab extends StatefulWidget {
  const SystemTab({super.key, required this.active});

  final bool active;

  @override
  State<SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<SystemTab> {
  final SystemStatsStore _store = SystemStatsStore.instance;
  _SubTab _tab = _SubTab.overview;

  bool _holdingLight = false;
  bool _holdingDetail = false;

  @override
  void initState() {
    super.initState();
    _syncLeases();
  }

  @override
  void didUpdateWidget(SystemTab old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncLeases();
  }

  @override
  void dispose() {
    _setLight(false);
    _setDetail(false);
    super.dispose();
  }

  /// Both pages want the process list — the overview shows process and thread
  /// counts, and it is where the disk poll is driven from — so the detail lease
  /// tracks the tab's visibility rather than the sub-tab.
  void _syncLeases() {
    _setLight(widget.active);
    _setDetail(widget.active);
  }

  void _setLight(bool want) {
    if (want == _holdingLight) return;
    _holdingLight = want;
    want ? _store.acquireLight() : _store.releaseLight();
  }

  void _setDetail(bool want) {
    if (want == _holdingDetail) return;
    _holdingDetail = want;
    want ? _store.acquireDetail() : _store.releaseDetail();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSubTabs(theme),
          Container(height: 1, color: theme.divider),
          Expanded(
            // IndexedStack again, for the same reason the overlay uses one: the
            // process table owns sort, filter, and expansion state that must
            // survive a trip to the overview and back.
            child: IndexedStack(
              index: _tab.index,
              sizing: StackFit.expand,
              children: [
                OverviewPage(store: _store),
                ProcessTable(store: _store),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubTabs(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SubTabButton(
            icon: FontAwesomeIcons.gaugeHigh,
            label: 'Overview',
            selected: _tab == _SubTab.overview,
            onTap: () => setState(() => _tab = _SubTab.overview),
          ),
          const SizedBox(width: 4),
          _SubTabButton(
            icon: FontAwesomeIcons.listUl,
            label: 'Processes',
            selected: _tab == _SubTab.processes,
            onTap: () => setState(() => _tab = _SubTab.processes),
          ),
        ],
      ),
    );
  }
}

/// The underline treatment the system monitor's bar popup already uses, so the
/// two surfaces of the same feature look like each other.
class _SubTabButton extends StatefulWidget {
  const _SubTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final FaIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SubTabButton> createState() => _SubTabButtonState();
}

class _SubTabButtonState extends State<_SubTabButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final Color color;
    if (widget.selected) {
      color = theme.accent;
    } else if (_hovered) {
      color = theme.popupForeground;
    } else {
      color = theme.popupForeground.withValues(alpha: 0.6);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: widget.selected ? theme.accent : const Color(0x00000000),
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FaIcon(widget.icon, size: 11, color: color),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: theme.fontFamily,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.normal,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
