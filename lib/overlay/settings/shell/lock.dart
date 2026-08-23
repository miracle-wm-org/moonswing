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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final path = (store.get<String>(['lock', 'background']) ?? '').trim();
    final missing = path.isNotEmpty && !File(path).existsSync();

    return SettingsSection(
      label: 'Lock Screen',
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
                  path.isEmpty ? 'Default wallpaper' : path.split('/').last,
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
            'That file no longer exists — the shipped default will be used '
            'until you choose another.',
          ),
        SettingsRow(
          label: 'Fit',
          control: SettingsSegmented(
            options: const ['fill', 'contain', 'natural'],
            value: store.get<String>(['lock', 'fit']) ?? 'fill',
            onChanged: (v) => store.set(['lock', 'fit'], v),
          ),
        ),
        SettingsRow(
          label: 'Show name',
          control: SettingsToggle(
            value: store.get<bool>(['lock', 'show_username']) ?? true,
            onChanged: (v) => store.set(['lock', 'show_username'], v),
          ),
        ),
        SettingsRow(
          label: 'Blur when unlocking',
          control: SettingsNumberField(
            value: store.get<num>(['lock', 'blur_sigma']) ?? 18,
            isInt: false,
            onChanged: (v) => store.set(
              ['lock', 'blur_sigma'],
              v.toDouble().clamp(0.0, 100.0),
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
