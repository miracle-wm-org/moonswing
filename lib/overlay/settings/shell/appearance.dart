import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/font_catalog.dart';
import 'package:graceful_shell/theme/popup_effect.dart';
import 'package:graceful_shell/theme/theme_store.dart';

/// Theme picker + editor.
///
/// The palette no longer lives in `config.toml` — [ThemeStore] owns a file
/// per theme under `~/.config/graceful-shell/themes/` and `config.toml` only
/// names the active one. So this section talks to [ThemeStore], not [store];
/// the parameter stays because every category builder takes one.
class AppearanceSection extends StatefulWidget {
  const AppearanceSection({super.key, required this.store});

  final ConfigStore store;

  @override
  State<AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<AppearanceSection> {
  final ThemeStore _themes = ThemeStore.instance;
  bool _naming = false;

  /// Started once, here rather than in `build`: this section rebuilds on every
  /// ThemeStore notify, which includes every frame of a colour-picker drag.
  final Future<List<String>> _fonts = FontCatalog.instance.list();

  static const Map<String, String> _colorLabels = {
    'accent': 'Accent',
    'foreground': 'Foreground',
    'surface_hover': 'Surface (hover)',
    'surface_pressed': 'Surface (pressed)',
    'workspace_background': 'Workspace background',
    'popup_background': 'Popup background',
    'popup_foreground': 'Popup foreground',
    'control_surface': 'Control surface',
    'slider_track': 'Slider track',
    'muted': 'Muted text',
    'divider': 'Divider',
    'panel_background': 'Panel background',
    'panel_border': 'Panel border',
    'popup_border': 'Popup border',
    'popup_shadow_color': 'Popup shadow',
    'scrim': 'Overlay scrim',
  };

  void _duplicate() => setState(() => _themes.duplicateActive());

  String _activeDisplayName() => _themes.themes
      .firstWhere(
        (t) => t.slug == _themes.activeName,
        orElse: () => _themes.themes.first,
      )
      .displayName;

  @override
  Widget build(BuildContext context) {
    // A sliver group rather than a Column: this section *is* the Appearance
    // page, and the page's scroller is a `CustomScrollView`. See
    // [SliverSettingsSection].
    return SliverMainAxisGroup(
      slivers: [
        SliverSettingsSection(
          label: 'Theme',
          // On the section's heading rather than under the swatch grid: the
          // grid is a Wrap that grows a row per handful of themes, so the one
          // control that adds another was drifting down the pane as it filled.
          trailing: SettingsAddButton(
            label: 'New theme…',
            onTap: () => setState(() => _naming = !_naming),
          ),
          children: [
            // Revealed above the grid, so the field stays put as the grid
            // grows under it.
            if (_naming) ...[
              _NewThemeRow(
                onCancel: () => setState(() => _naming = false),
                onSubmit: (name) {
                  final slug = _themes.create(name);
                  if (slug != null) setState(() => _naming = false);
                },
              ),
              const SizedBox(height: 12),
            ],
            // Rebuilt on every ThemeStore change: the cards preview the
            // palettes themselves, so a colour edit — including every frame of
            // a picker drag — has to repaint the active card's swatches, and a
            // switch made from anywhere has to move the tick.
            ListenableBuilder(
              listenable: _themes,
              builder: (context, _) {
                final active = _themes.activeName;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final summary in _themes.themes)
                      _ThemeCard(
                        summary: summary,
                        selected: summary.slug == active,
                        onTap: () => _themes.select(summary.slug),
                        onDelete: summary.builtIn
                            ? null
                            : () => _themes.delete(summary.slug),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            SettingsHint(
              'Themes are files in ${_themes.directory}. '
              'Drop one in to add it by hand.',
            ),
          ],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
        // The editor's structure — which rows exist, their keys, the read-only
        // state, the seed values of the self-managing fields — depends only on
        // *which* theme is active, not on the palette's current values. So it
        // rebuilds only when the active theme changes (a switch, a duplicate,
        // a create), never on the per-frame notifies of a colour-picker drag:
        // the swatch grid above and the field being dragged are the only
        // widgets that repaint mid-drag.
        StoreSelector<(String, bool, String)>(
          listenable: _themes,
          selector: () => (
            _themes.activeName,
            _themes.activeIsBuiltIn,
            _activeDisplayName(),
          ),
          builder: (context, selection) {
            final (active, builtIn, displayName) = selection;
            // Read straight off the resolved theme rather than the file, so a
            // key the file omits shows the value actually in use.
            final current = _themes.theme.toMap();
            return SliverSettingsSection(
              label: 'Edit $displayName',
              children: [
                if (builtIn) ...[
                  const SettingsHint(
                    'This theme ships with the shell and is read-only — the '
                    'next update would overwrite your changes. Duplicate it to '
                    'make it yours.',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsOptionButton(
                      label: 'Duplicate to edit',
                      selected: false,
                      onTap: _duplicate,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SettingsRow(
                  label: 'Font',
                  // Unlike the keyed fields below, the font control renders
                  // its current value on every build, so it follows the store
                  // itself — one row, cheap — or a pick would not show.
                  control: StoreSelector<String>(
                    listenable: _themes,
                    // The field, not `toMap()['font']`: this selector runs on
                    // *every* ThemeStore notify, and `toMap` builds a thirty-key
                    // map — twice per frame of a colour-picker drag, between
                    // this row and the panel-gradient one below.
                    selector: () => _themes.theme.fontFamily,
                    builder: (context, font) => FutureBuilder<List<String>>(
                      future: _fonts,
                      builder: (context, snapshot) {
                        final fonts = snapshot.data;
                        final value = font;
                        if (fonts == null || fonts.isEmpty) {
                          // Still loading, or no fontconfig on this machine.
                          // The key stays editable by hand either way.
                          return SettingsTextField(
                            // Keyed on the theme so switching re-seeds the
                            // field — SettingsTextField reads `initial` only
                            // on first build.
                            key: ValueKey('font-$active'),
                            width: 180,
                            initial: value,
                            onChanged: (v) => _themes.edit('font', v.trim()),
                          );
                        }
                        return SettingsFontField(
                          value: value,
                          // A theme naming a family this machine does not have
                          // still shows, and stays the selected row, rather
                          // than reading as somebody else's font.
                          fonts: fonts.contains(value)
                              ? fonts
                              : <String>[value, ...fonts],
                          locked: builtIn,
                          onLockedTap: _duplicate,
                          onChanged: (v) => _themes.edit('font', v),
                        );
                      },
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Font size',
                  control: SettingsNumberField(
                    key: ValueKey('font_size-$active'),
                    value: current['font_size'] as num? ?? ShellFontSizes.body,
                    isInt: false,
                    // Straight to `edit`, like the panel numbers below rather
                    // than like the toggle above: `edit` forks a built-in
                    // itself, and answering a typed digit with a duplicate
                    // would throw the digit away.
                    onChanged: (v) => _themes.edit(
                      'font_size',
                      v.toDouble().clamp(6.0, 32.0),
                    ),
                  ),
                ),
                const SettingsHint(
                  "The size of the shell's body text, and with it every other "
                  'size — labels, captions and headings keep their proportions '
                  'either side of it, in the panels and in everything they '
                  'open. Bar thickness is its own setting, under Panels & '
                  'Layout: a much larger font wants a taller bar to sit in.',
                ),
                const SizedBox(height: 8),
                SettingsRow(
                  label: 'Panel gradient',
                  // Renders its value too, so it follows the store like the
                  // font row does.
                  control: StoreSelector<bool>(
                    listenable: _themes,
                    // The field, for the reason the font row above states.
                    selector: () => _themes.theme.panelGradient,
                    builder: (context, gradient) => SettingsToggle(
                      value: gradient,
                      onChanged: builtIn
                          ? (_) => _duplicate()
                          : (v) => _themes.edit('panel_gradient', v),
                    ),
                  ),
                ),
                const SettingsHint(
                  'Off paints the bar as a flat panel background. On fades it '
                  'from the accent across to that colour, with every stop at '
                  "the panel background's alpha — so the bar has one opacity.",
                ),
                const SizedBox(height: 8),
                SettingsRow(
                  label: 'Panel margin',
                  control: SettingsNumberField(
                    key: ValueKey('panel_margin-$active'),
                    value: current['panel_margin'] as num? ?? 0,
                    isInt: true,
                    onChanged: (v) =>
                        _themes.edit('panel_margin', v.toInt().clamp(0, 256)),
                  ),
                ),
                SettingsRow(
                  label: 'Panel corner radius',
                  control: SettingsNumberField(
                    key: ValueKey('panel_radius-$active'),
                    value: current['panel_radius'] as num? ?? 0,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'panel_radius',
                      v.toDouble().clamp(0.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Panel border width',
                  control: SettingsNumberField(
                    key: ValueKey('panel_border_width-$active'),
                    value: current['panel_border_width'] as num? ?? 0,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'panel_border_width',
                      v.toDouble().clamp(0.0, 16.0),
                    ),
                  ),
                ),
                const SettingsHint(
                  'A margin floats the bar off the screen edges. The gap is '
                  'real — windows will not tile into it, and clicks that land '
                  'there reach the desktop. A floating bar rounds all four '
                  'corners; one with no margin rounds only the two facing the '
                  "screen, so the display's own corners stay square. The "
                  'border draws only at a width above zero.',
                ),
                const SizedBox(height: 8),
                SettingsRow(
                  label: 'Popup corner radius',
                  control: SettingsNumberField(
                    key: ValueKey('popup_radius-$active'),
                    // The fallbacks are the ThemeConfig defaults, not 0: a
                    // theme file written before these keys existed has neither,
                    // and a field reading 0 while the shell paints 8 would be
                    // an edit the user never made.
                    value: current['popup_radius'] as num? ?? 8,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'popup_radius',
                      v.toDouble().clamp(0.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup gap from bar',
                  control: SettingsNumberField(
                    key: ValueKey('popup_gap-$active'),
                    value: current['popup_gap'] as num? ?? 0,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'popup_gap',
                      v.toDouble().clamp(0.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup join flare',
                  control: SettingsNumberField(
                    key: ValueKey('popup_attach_radius-$active'),
                    value: current['popup_attach_radius'] as num? ?? 0,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'popup_attach_radius',
                      v.toDouble().clamp(0.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup border width',
                  control: SettingsNumberField(
                    key: ValueKey('popup_border_width-$active'),
                    value: current['popup_border_width'] as num? ?? 1,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'popup_border_width',
                      v.toDouble().clamp(0.0, 16.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup shadow blur',
                  control: SettingsNumberField(
                    key: ValueKey('popup_shadow_blur-$active'),
                    value: current['popup_shadow_blur'] as num? ?? 16,
                    isInt: false,
                    onChanged: (v) => _themes.edit(
                      'popup_shadow_blur',
                      v.toDouble().clamp(0.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup shadow spread',
                  control: SettingsNumberField(
                    key: ValueKey('popup_shadow_spread-$active'),
                    value: current['popup_shadow_spread'] as num? ?? 0,
                    isInt: false,
                    allowNegative: true,
                    onChanged: (v) => _themes.edit(
                      'popup_shadow_spread',
                      v.toDouble().clamp(-32.0, 32.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup shadow offset X',
                  control: SettingsNumberField(
                    key: ValueKey('popup_shadow_offset_x-$active'),
                    value: current['popup_shadow_offset_x'] as num? ?? 0,
                    isInt: false,
                    allowNegative: true,
                    onChanged: (v) => _themes.edit(
                      'popup_shadow_offset_x',
                      v.toDouble().clamp(-64.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup shadow offset Y',
                  control: SettingsNumberField(
                    key: ValueKey('popup_shadow_offset_y-$active'),
                    value: current['popup_shadow_offset_y'] as num? ?? 6,
                    isInt: false,
                    allowNegative: true,
                    onChanged: (v) => _themes.edit(
                      'popup_shadow_offset_y',
                      v.toDouble().clamp(-64.0, 64.0),
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Popup animation',
                  control: SettingsDropdown<PopupEffect>(
                    key: ValueKey('popup_animation-$active'),
                    // `description`, not `detail`: a sentence in the tag slot
                    // is laid out unflexed beside the label, so it took the
                    // whole row, ellipsised the name to nothing and was then
                    // clipped by a card sized to a trigger reading "Fade". A
                    // description wraps, and is what gives the card a width of
                    // its own — see [SettingsDropdown.cardWidth].
                    items: [
                      for (final effect in PopupEffect.values)
                        SettingsDropdownItem<PopupEffect>(
                          value: effect,
                          label: effect.label,
                          description: effect.description,
                        ),
                    ],
                    // The resolved theme's, so a file written before this key
                    // existed shows the effect actually being played rather
                    // than an empty row.
                    selected:
                        PopupEffect.fromSlug(
                          current['popup_animation'] as String?,
                        ) ??
                        PopupEffect.slide,
                    // Straight to `edit`, like the numbers above: it forks a
                    // built-in itself, and answering a pick with a duplicate
                    // would throw the pick away.
                    onSelected: (v) => _themes.edit('popup_animation', v.slug),
                  ),
                ),
                const SettingsHint(
                  'Popup, menu, flyout and on-screen-indicator cards. A popup '
                  'opened from the bar is anchored to the bar\'s inner edge and '
                  'centred on the button that opened it. The gap is how far off '
                  'that edge it sits, and a gap of zero attaches it: the card '
                  'goes flush against the bar, the two corners touching it '
                  'are squared off, and the rim and shadow on that edge are '
                  'dropped, so the popup reads as growing out of the bar. The '
                  'join flare sweeps those two corners outward *into* the bar — '
                  'the inverse of a rounded corner, so the card is widest '
                  'exactly where it meets the bar rather than pulling away from '
                  'it. It is unread at any other gap. The rim is what gives a translucent card an edge '
                  'over a busy wallpaper, and draws only at a width above zero. '
                  'The shadow enlarges the popup\'s own window to make room for '
                  'itself, and the popup is repositioned by the same amount so '
                  'the card stays where it always sat; a fully transparent '
                  'shadow colour turns it off. The animation is how the card '
                  'arrives — and, played backwards, how it leaves, so the way '
                  'out is always the way in reversed. Slide and Grow travel '
                  'out of the bar the popup belongs to, so a bottom bar\'s '
                  'menus rise where a top bar\'s drop; None is a real off '
                  'switch, and is what the dock uses whatever this says, '
                  'because its labels come and go under a moving pointer.',
                ),
                const SizedBox(height: 8),
                const SettingsHint(
                  'The wash behind the settings and launcher panels is the '
                  'overlay scrim below. There is no blur control: a shell '
                  'surface is transparent and the compositor owns what is '
                  'under it, so translucency comes from the alpha channel of '
                  'the colours below.',
                ),
                const SizedBox(height: 8),
                for (final entry in _colorLabels.entries)
                  SettingsRow(
                    label: entry.value,
                    control: SettingsColorField(
                      key: ValueKey('${entry.key}-$active'),
                      initial: current[entry.key] as String? ?? '#000000',
                      locked: builtIn,
                      onLockedTap: _duplicate,
                      onChanged: (v) => _themes.edit(entry.key, v),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// One theme in the picker: a strip of its own colours, its name, and a tick
/// when it is the active one. Drawn in the theme it represents, so the grid
/// previews rather than describes.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.summary,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final ThemeSummary summary;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final preview = summary.config;
    // The swatch strip, the name and the slug depend on the palette and on
    // `selected`, never on `hovered`, so they are built once here and captured.
    // See [SettingsRow] for why the builder is kept down to a decoration.
    final swatches = Container(
      height: 34,
      decoration: BoxDecoration(
        color: preview.workspaceBackground,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: preview.divider),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          for (final c in [
            preview.accent,
            preview.surfacePressed,
            preview.popupBackground,
            preview.foreground,
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: preview.divider),
                ),
              ),
            ),
        ],
      ),
    );
    final name = Expanded(
      child: Text(
        summary.displayName,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: ShellFontSizes.body,
          fontFamily: theme.fontFamily,
          color: theme.popupForeground,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
    final slug = Text(
      summary.builtIn ? 'Built-in' : summary.slug,
      style: TextStyle(
        fontSize: ShellFontSizes.caption,
        fontFamily: theme.fontFamily,
        color: theme.muted,
      ),
    );
    // Not inside a [SettingsRow], so it carries its own — see that class for
    // the rule.
    return RepaintBoundary(
      child: HoverRegion(
        onTap: onTap,
        builder: (context, hovered) => Container(
          width: 168,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovered ? theme.surfaceHover : theme.controlSurface,
            borderRadius: BorderRadius.circular(ShellRadii.card),
            border: Border.all(
              color: selected ? theme.accent : theme.divider,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The swatches sit on the preview's own background, or a
              // translucent theme would be judged against the wrong surface.
              swatches,
              const SizedBox(height: 8),
              Row(
                children: [
                  name,
                  // The slot is occupied whether or not either glyph is in it.
                  // A tick is 11px and a [SettingsIconButton] is 26 square, so
                  // swapping one for the other on hover marked the card needing
                  // *layout* — and a RepaintBoundary contains a repaint but
                  // never a relayout, so the mark walked straight past it and
                  // re-laid the whole Wrap under the pointer. `panels.dart`'s
                  // `_PanelTab` reserves its close button's square for the same
                  // reason.
                  SizedBox.square(
                    dimension: ShellSizes.iconButtonDense,
                    child: Center(
                      child: selected
                          ? FaIcon(
                              FontAwesomeIcons.check,
                              size: ShellFontSizes.caption,
                              color: theme.accent,
                            )
                          : (hovered && onDelete != null)
                          ? SettingsIconButton(
                              icon: FontAwesomeIcons.trash,
                              size: ShellFontSizes.caption,
                              box: ShellSizes.iconButtonDense,
                              onTap: onDelete!,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              slug,
            ],
          ),
        ),
      ),
    );
  }
}

/// Name entry for "New theme…". The name is slugified into a filename, so an
/// empty or punctuation-only name is refused rather than written.
class _NewThemeRow extends StatefulWidget {
  const _NewThemeRow({required this.onSubmit, required this.onCancel});

  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_NewThemeRow> createState() => _NewThemeRowState();
}

class _NewThemeRowState extends State<_NewThemeRow> {
  String _name = '';

  bool get _valid =>
      _name.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SettingsTextField(
          width: 200,
          initial: '',
          onChanged: (v) => setState(() => _name = v),
        ),
        const SizedBox(width: 8),
        SettingsOptionButton(
          label: 'Create',
          selected: _valid,
          onTap: () {
            if (_valid) widget.onSubmit(_name);
          },
        ),
        const SizedBox(width: 6),
        SettingsIconButton(
          icon: FontAwesomeIcons.xmark,
          size: 12,
          onTap: widget.onCancel,
        ),
      ],
    );
  }
}
