import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/module.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/underline_tabs.dart';

/// The Panels & Layout category: a tab per configured panel over that panel's
/// geometry and module-slot editors, plus an "Add panel" tab.
class PanelsSection extends StatefulWidget {
  const PanelsSection({super.key, required this.store});

  final ConfigStore store;

  @override
  State<PanelsSection> createState() => _PanelsSectionState();
}

class _PanelsSectionState extends State<PanelsSection> {
  /// Known anchor names — used only to give a freshly-added panel a sensible
  /// default anchor (a panel named `left` anchors left). Panels are NOT
  /// created for these by default; the user adds each one manually.
  static const _anchors = ['top', 'bottom', 'left', 'right'];

  int _selected = 0;
  bool _adding = false;

  /// The module registry is fixed after `main()` runs, and `registeredKeys`
  /// mints a fresh iterable — this used to be allocated three times per build
  /// of the panel form, once per module slot.
  late final List<String> _moduleKeys = Module.registeredKeys.toList();

  final _nameController = TextEditingController();
  final _nameFocus = FocusNode();

  ConfigStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _title(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  void _startAdd() {
    setState(() => _adding = true);
    _nameFocus.requestFocus();
  }

  void _cancelAdd() {
    setState(() {
      _adding = false;
      _nameController.clear();
    });
  }

  void _commitAdd(List<String> existing) {
    final name = _nameController.text.trim();
    if (name.isEmpty || existing.contains(name)) {
      _cancelAdd();
      return;
    }
    // Writing the anchor creates the `[panels.<name>]` table (ConfigStore.set
    // builds intermediate tables); a known anchor name seeds its own position.
    store.set([
      'panels',
      name,
      'anchor',
    ], _anchors.contains(name) ? name : 'top');
    setState(() {
      _adding = false;
      _nameController.clear();
      _selected = existing.length; // new panel is appended at the end
    });
  }

  /// Deletes `[panels.<name>]` outright, behind a confirmation.
  ///
  /// No restart wiring is needed: `ConfigStore._restartSignature` folds every
  /// panel key, so dropping one raises the restart banner on its own.
  Future<void> _removePanel(String name) async {
    final title = _title(name);
    final names = store.panelNames;
    // Read before the await: the count is what the warning is about, and the
    // name is what survives the removal renumbering every index after it.
    final isLast = names.length <= 1;
    final selectedName = names.isEmpty
        ? null
        : names[_selected.clamp(0, names.length - 1)];
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Remove the $title panel?',
      message:
          'The $title panel and everything under it — its geometry '
          'and its module layout — are deleted from config.toml. This '
          'cannot be undone.',
      warning: isLast
          // Not hypothetical: AppConfig.fromMap substitutes a single default
          // panel when `[panels]` is empty, so saying nothing here would make
          // the panel look like it came back on its own.
          ? 'This is the last panel. With none configured, the shell falls '
                'back to a single default panel the next time it starts.'
          : null,
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    store.remove(['panels', name]);
    setState(() {
      _adding = false;
      final remaining = store.panelNames;
      // Follow the panel the user was editing rather than the index holding
      // it: removing a tab to its left shifts it down one, and clamping alone
      // would silently land the form on a different panel. Removing the
      // selected one falls back to whatever now occupies its slot.
      final kept = selectedName == null || selectedName == name
          ? -1
          : remaining.indexOf(selectedName);
      _selected = kept >= 0
          ? kept
          : (remaining.isEmpty ? 0 : _selected.clamp(0, remaining.length - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    // The section's *structure* moves only when a panel is added or removed, so
    // it is selected on the name list and nothing else — the geometry rows below
    // subscribe per key. Under the page-level `ListenableBuilder` this replaces,
    // every keystroke anywhere in the settings UI re-walked `store.panelNames`.
    return StoreSelector<String>(
      listenable: store,
      selector: () => store.panelNames.join('\u0000'),
      builder: (context, _) => _buildSection(context),
    );
  }

  Widget _buildSection(BuildContext context) {
    final names = store.panelNames;
    final selected = names.isEmpty ? -1 : _selected.clamp(0, names.length - 1);
    return SliverSettingsSection(
      label: 'Panels & Layout',
      children: [
        _buildTabs(names, selected),
        if (_adding) _buildAddField(names),
        if (selected < 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SettingsHint(
              _adding
                  ? 'Name the panel, then press Enter.'
                  : 'No panels yet. '
                        'Use “Add panel” to create one.',
            ),
          )
        else
          _buildPanel(names[selected]),
      ],
    );
  }

  Widget _buildTabs(List<String> names, int selected) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.divider)),
        ),
        // "Add panel" is pinned to the strip's right edge, outside the
        // scroller: as the last item *inside* it, the one control that
        // creates a panel scrolled out of reach exactly when there were
        // enough panels to want another.
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < names.length; i++)
                      _PanelTab(
                        label: _title(names[i]),
                        selected: i == selected && !_adding,
                        onTap: () => setState(() {
                          _selected = i;
                          _adding = false;
                        }),
                        onRemove: () => _removePanel(names[i]),
                      ),
                  ],
                ),
              ),
            ),
            _PanelTab(
              label: 'Add panel',
              icon: FontAwesomeIcons.plus,
              selected: _adding,
              onTap: _startAdd,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddField(List<String> existing) {
    final theme = ThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.popupBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _nameFocus.hasFocus ? theme.accent : theme.divider,
                ),
              ),
              child: Stack(
                children: [
                  if (_nameController.text.isEmpty)
                    Text(
                      'Panel name (e.g. top)',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.popupForeground.withValues(alpha: 0.35),
                        fontFamily: theme.fontFamily,
                      ),
                    ),
                  EditableText(
                    controller: _nameController,
                    focusNode: _nameFocus,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.popupForeground,
                      fontFamily: theme.fontFamily,
                    ),
                    cursorColor: theme.accentText,
                    backgroundCursorColor: theme.divider,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _commitAdd(existing),
                  ),
                ],
              ),
            ),
          ),
          SettingsIconButton(
            icon: FontAwesomeIcons.check,
            onTap: () => _commitAdd(existing),
          ),
          SettingsIconButton(icon: FontAwesomeIcons.xmark, onTap: _cancelAdd),
        ],
      ),
    );
  }

  Widget _buildPanel(String name) {
    List<String> p(List<String> rest) => ['panels', name, ...rest];
    // A not-yet-defined anchor panel defaults its anchor to its own position.
    final defaultAnchor = _anchors.contains(name) ? name : 'top';
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsRow.field(
            SettingsCatalog.panelHeight,
            control: ConfigValue<num>(
              store: store,
              path: p(['height']),
              fallback: 32,
              builder: (context, value) => SettingsNumberField(
                value: value!,
                isInt: true,
                onChanged: (v) => store.set(p(['height']), v),
              ),
            ),
          ),
          SettingsRow.field(
            SettingsCatalog.panelPaddingHorizontal,
            control: ConfigValue<num>(
              store: store,
              path: p(['padding_horizontal']),
              fallback: 8,
              builder: (context, value) => SettingsNumberField(
                value: value!,
                isInt: true,
                onChanged: (v) => store.set(p(['padding_horizontal']), v),
              ),
            ),
          ),
          SettingsRow.field(
            SettingsCatalog.panelAnchor,
            control: ConfigValue<String>(
              store: store,
              path: p(['anchor']),
              fallback: defaultAnchor,
              builder: (context, value) => SettingsSegmented(
                options: const ['top', 'bottom', 'left', 'right'],
                value: value!,
                onChanged: (v) => store.set(p(['anchor']), v),
              ),
            ),
          ),
          SettingsRow.field(
            SettingsCatalog.panelLayer,
            control: ConfigValue<String>(
              store: store,
              path: p(['layer']),
              fallback: 'top',
              builder: (context, value) => SettingsSegmented(
                options: const ['background', 'bottom', 'top', 'overlay'],
                value: value!,
                onChanged: (v) => store.set(p(['layer']), v),
              ),
            ),
          ),
          for (final slot in const ['left', 'center', 'right'])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              // The editor renders the slot's heading itself, so its "Add module"
              // button sits on that heading's right rather than under a list the
              // third slot had already pushed off the pane.
              //
              // Selected on the joined list rather than the list itself: `getList`
              // mints a fresh `List<String>` per call and `List` has no value
              // equality, so a bare selector would report a change on every notify.
              child: StoreSelector<String>(
                listenable: store,
                selector: () =>
                    store.getList<String>(p(['layout', slot])).join('\u0000'),
                builder: (context, _) => SettingsStringListEditor(
                  label: '${slot[0].toUpperCase()}${slot.substring(1)} modules',
                  addLabel: 'Add module',
                  items: store.getList<String>(p(['layout', slot])),
                  onChanged: (list) => store.set(p(['layout', slot]), list),
                  suggestions: _moduleKeys,
                  width: null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single tab in the Panels & Layout tab strip: the shared [UnderlineTab]
/// at this strip's sizes, plus the close button that surfaces while the tab
/// is selected or hovered. The outer [HoverRegion] tracks the whole tab for
/// that reveal; [UnderlineTab] owns the underline and foreground treatment.
class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FaIconData? icon;

  /// Deletes the panel this tab names. Null on the "Add panel" tab, which is
  /// the one tab with nothing to delete.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    // Not inside a [SettingsRow], so it carries its own — see that class for
    // the rule.
    return RepaintBoundary(
      child: HoverRegion(
        builder: (context, hovered) => UnderlineTab(
          label: label,
          selected: selected,
          onTap: onTap,
          icon: icon,
          iconSize: 11,
          fontSize: 13,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          trailing: onRemove == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 6),
                    // The slot is occupied whether or not the button is in it: a
                    // tab that grew on hover would shove every tab to its right
                    // along inside the scrolling strip, under the pointer.
                    SizedBox.square(
                      dimension: _kPanelTabCloseSize,
                      child: selected || hovered
                          ? _PanelTabClose(onTap: onRemove!)
                          : null,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The side of the square reserved for a tab's remove button.
const double _kPanelTabCloseSize = 18;

/// The x on a panel tab.
///
/// Its own recognizer nested inside the tab's: the gesture arena resolves to the
/// deepest competitor, so a click here removes the panel rather than also
/// selecting the tab. Not a [SettingsIconButton] — that control is 26 square and
/// would out-measure the tab's own text.
class _PanelTabClose extends StatelessWidget {
  const _PanelTabClose({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : const Color(0x00000000),
          borderRadius: BorderRadius.circular(ShellRadii.barButton),
        ),
        child: FaIcon(
          FontAwesomeIcons.xmark,
          size: 10,
          color: hovered
              ? theme.accentText
              : theme.popupForeground.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
