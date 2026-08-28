import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:graceful_shell/config_store.dart';
import 'package:graceful_shell/overlay/file_picker.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/scopes.dart';

/// The lock screen's wallpaper and chrome.
///
/// Unlike the desktop background this is a single wallpaper — a lock screen
/// has no reason to rotate through several — but it accepts video as well as
/// stills, rendered by the same `MediaBackground`.
class LockSection extends StatefulWidget {
  const LockSection({super.key, required this.store});

  final ConfigStore store;

  @override
  State<LockSection> createState() => _LockSectionState();
}

class _LockSectionState extends State<LockSection> {
  ConfigStore get store => widget.store;

  Future<void> _chooseWallpaper() async {
    final paths = await showFilePicker(
      context,
      filters: [
        FilePickerFilter.wallpapers,
        FilePickerFilter.images,
        FilePickerFilter.videos,
        FilePickerFilter.all,
      ],
      allowMultiple: false,
    );
    if (paths == null || paths.isEmpty) return;
    store.set(['lock', 'background'], paths.first);
  }

  /// The last wallpaper path this section stat'd, and what it answered.
  ///
  /// `existsSync` is a syscall and `build` is not the place for one — this ran
  /// on every keystroke anywhere in the settings UI for as long as the pane sat
  /// under a page-level `ListenableBuilder`. The [ConfigValue] below narrows
  /// *when* the builder runs; this makes a run that is not a path change free.
  String? _statPath;
  bool _statMissing = false;

  bool _isMissing(String path) {
    if (path == _statPath) return _statMissing;
    _statPath = path;
    _statMissing = path.isNotEmpty && !File(path).existsSync();
    return _statMissing;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);

    return SliverSettingsSection(
      label: 'Lock Screen',
      children: [
        // One subscription spanning the row and the "no longer exists" hint
        // under it, which reads the same key. See [ConfigValue].
        ConfigValue<String>(
          store: store,
          path: const ['lock', 'background'],
          fallback: '',
          builder: (context, raw) {
            final path = (raw ?? '').trim();
            final missing = _isMissing(path);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsRow(
                  label: 'Wallpaper',
                  alignTop: true,
                  control: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SettingsOptionButton(
                            label: 'Choose…',
                            selected: false,
                            onTap: _chooseWallpaper,
                          ),
                          if (path.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            SettingsOptionButton(
                              label: 'Reset',
                              selected: false,
                              onTap: () => store.remove(['lock', 'background']),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 240,
                        child: Text(
                          path.isEmpty
                              ? 'Default wallpaper'
                              : path.split('/').last,
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: theme.fontFamily,
                            decoration: TextDecoration.none,
                            fontWeight: FontWeight.normal,
                            color: missing
                                ? const Color(0xFFE06C75)
                                : theme.popupForeground.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (missing)
                  const SettingsHint(
                    'That file no longer exists — the shipped default will be '
                    'used until you choose another.',
                  ),
              ],
            );
          },
        ),
        SettingsRow(
          label: 'Fit',
          control: ConfigValue<String>(
            store: store,
            path: const ['lock', 'fit'],
            fallback: 'fill',
            builder: (context, value) => SettingsSegmented(
              options: const ['fill', 'contain', 'natural'],
              value: value!,
              onChanged: (v) => store.set(['lock', 'fit'], v),
            ),
          ),
        ),
        SettingsRow(
          label: 'Show name',
          control: ConfigValue<bool>(
            store: store,
            path: const ['lock', 'show_username'],
            fallback: true,
            builder: (context, value) => SettingsToggle(
              value: value!,
              onChanged: (v) => store.set(['lock', 'show_username'], v),
            ),
          ),
        ),
        SettingsRow(
          label: 'Blur when unlocking',
          control: ConfigValue<num>(
            store: store,
            path: const ['lock', 'blur_sigma'],
            fallback: 18,
            builder: (context, value) => SettingsNumberField(
              value: value!,
              isInt: false,
              onChanged: (v) => store.set([
                'lock',
                'blur_sigma',
              ], v.toDouble().clamp(0.0, 100.0)),
            ),
          ),
        ),
        const SettingsHint(
          'How strongly the wallpaper blurs once the password field appears. '
          'Set to 0 to leave it sharp.',
        ),
      ],
    );
  }
}
