// The screen-share consent picker: a card of live monitor and window
// previews over a full-screen layer-shell backdrop, shown while the portal's
// `Start` call is blocked awaiting a choice.
//
// The sources and their preview feeds are injected, so widget tests drive the
// whole surface without touching Wayland.


import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../config.dart';
import '../scopes.dart';
import '../hover_region.dart';
import '../overlay_fade_scaffold.dart';
import 'picker_controller.dart';
import 'preview.dart';

/// One selectable source tile.
class PickerSource {
  const PickerSource({
    required this.key,
    required this.label,
    required this.sublabel,
    required this.picked,
    required this.frames,
  });

  /// Stable identity for selection state (connector or toplevel identifier).
  final String key;
  final String label;
  final String sublabel;

  /// What [ScreencastPickerController.complete] carries for this source.
  final PickedSource picked;

  /// Live preview feed; null renders the placeholder only.
  final PreviewFrames? frames;
}

const double kPickerCardWidth = 860;
const double kPickerTileWidth = 240;
const double kPickerTileHeight = 168;

class ScreencastPickerOverlay extends StatefulWidget {
  const ScreencastPickerOverlay({
    super.key,
    required this.request,
    required this.monitors,
    required this.windows,
    required this.closingNotifier,
    required this.onClosed,
    required this.onConfirm,
    required this.onCancel,
  });

  final PickRequest request;
  final List<PickerSource> monitors;
  final List<PickerSource> windows;

  /// Flipped by the owner to start the exit animation; [onClosed] follows.
  final ValueNotifier<bool> closingNotifier;
  final VoidCallback onClosed;

  final void Function(List<PickedSource> sources) onConfirm;
  final VoidCallback onCancel;

  @override
  State<ScreencastPickerOverlay> createState() =>
      _ScreencastPickerOverlayState();
}

class _ScreencastPickerOverlayState extends State<ScreencastPickerOverlay> {
  final Set<String> _selected = {};
  bool _answered = false;

  List<PickerSource> get _allSources => [...widget.monitors, ...widget.windows];

  void _toggle(PickerSource source) {
    setState(() {
      if (widget.request.multiple) {
        if (!_selected.remove(source.key)) _selected.add(source.key);
      } else {
        _selected
          ..clear()
          ..add(source.key);
      }
    });
  }

  void _confirm() {
    if (_answered || _selected.isEmpty) return;
    _answered = true;
    final picked = [
      for (final s in _allSources)
        if (_selected.contains(s.key)) s.picked,
    ];
    widget.onConfirm(picked);
    widget.closingNotifier.value = true;
  }

  /// Dismissal is a *denial* — the app gets response 1 and no stream.
  void _cancel() {
    if (_answered) return;
    _answered = true;
    widget.onCancel();
    widget.closingNotifier.value = true;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _cancel();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _confirm();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: theme.fontFamily,
          fontSize: 14,
          color: theme.popupForeground,
        ),
        child: Focus(
          autofocus: true,
          onKeyEvent: _onKey,
          // Backdrop tap dismisses, and dismissing denies the request.
          child: FadeOverlayScaffold(
            closing: widget.closingNotifier,
            onClosed: widget.onClosed,
            onBackdropTap: _cancel,
            child: _buildCard(theme),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(ThemeConfig theme) {
    final app = widget.request.appId;
    final title = app.isEmpty
        ? 'An application wants to share your screen'
        : 'Share your screen with $app';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kPickerCardWidth),
        child: Container(
          decoration: BoxDecoration(
            color: theme.popupBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.accent, width: 1.5),
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FaIcon(FontAwesomeIcons.display,
                      size: 16, color: theme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.popupForeground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.request.multiple
                    ? 'Pick one or more sources to share.'
                    : 'Pick what to share.',
                style: TextStyle(fontSize: 12, color: theme.muted),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.monitors.isNotEmpty)
                        _buildSection(theme, 'Screens', widget.monitors),
                      if (widget.windows.isNotEmpty)
                        _buildSection(theme, 'Windows', widget.windows),
                      if (_allSources.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            'Nothing available to share.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _PickerButton(
                    theme: theme,
                    label: 'Cancel',
                    onPressed: _cancel,
                  ),
                  const SizedBox(width: 10),
                  _PickerButton(
                    theme: theme,
                    label: 'Share',
                    primary: true,
                    onPressed: _selected.isEmpty ? null : _confirm,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
      ThemeConfig theme, String title, List<PickerSource> sources) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.muted,
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final source in sources)
                _SourceTile(
                  theme: theme,
                  source: source,
                  selected: _selected.contains(source.key),
                  onTap: () => _toggle(source),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.theme,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final ThemeConfig theme;
  final PickerSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final frames = source.frames;
    return HoverRegion(
      onTap: onTap,
      builder: (context, hovered) => SizedBox(
        width: kPickerTileWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: kPickerTileHeight,
              decoration: BoxDecoration(
                color: theme.controlSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? theme.accent : theme.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: frames == null
                  ? Center(
                      child: FaIcon(FontAwesomeIcons.display,
                          size: 28, color: theme.muted),
                    )
                  : CapturePreview(
                      frames: frames,
                      placeholderColor: theme.controlSurface,
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              source.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color:
                    selected ? theme.accent : theme.popupForeground,
              ),
            ),
            if (source.sublabel.isNotEmpty)
              Text(
                source.sublabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: theme.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.theme,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final ThemeConfig theme;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return HoverRegion(
      enabled: enabled,
      onTap: onPressed ?? () {},
      builder: (context, hovered) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: primary
              ? (enabled ? theme.accent : theme.surfacePressed)
              : theme.controlSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primary ? theme.accent : theme.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: primary
                ? (enabled ? theme.popupBackground : theme.muted)
                : theme.popupForeground,
          ),
        ),
      ),
    );
  }
}
