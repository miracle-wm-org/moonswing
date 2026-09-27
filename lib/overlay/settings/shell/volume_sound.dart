import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config_store.dart';
import 'package:moonswing/osd/volume_sound.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// The sound a volume change makes — `[osd] volume_sound`.
///
/// Both rows are live: the root hands every config change to
/// [VolumeSoundStore], and the next press of a volume key plays the new
/// sound. The preview goes through the same store, so what it plays — or the
/// reason it plays nothing — is exactly what a key press would get.
class VolumeSoundSection extends StatelessWidget {
  const VolumeSoundSection({super.key, required this.store, this.sound});

  final ConfigStore store;

  /// Injected for tests; the process-wide store otherwise.
  final VolumeSoundStore? sound;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final sound = this.sound ?? VolumeSoundStore.instance;

    return SliverSettingsSection(
      label: 'Volume Sound',
      children: [
        SettingsRow.field(
          SettingsCatalog.osdVolumeSound,
          info: 'The shipped sounds are $kVolumeSoundHint. '
              '“$kFreedesktopVolumeSound” is the stock sound from '
              'sound-theme-freedesktop, if it is installed; any other name '
              'is looked up in the sound themes the same way.',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Free-typed for the reason the chime's and the timer's rows
              // are: a sound-theme name and a path to the user's own file are
              // two answers a fixed list cannot hold.
              ConfigValue<String>(
                store: store,
                path: const ['osd', 'volume_sound'],
                fallback: kDefaultVolumeSound,
                builder: (context, value) => SettingsCommitField(
                  initial: value!,
                  hint: kVolumeSoundHint,
                  width: 220,
                  onCommitted: (value) =>
                      store.set(['osd', 'volume_sound'], value.trim()),
                ),
              ),
              const SizedBox(width: 6),
              // Offered even while silent: pressing it then is how a user
              // finds out that "none" is what they have.
              SettingsIconButton(
                icon: FontAwesomeIcons.play,
                size: ShellFontSizes.secondary,
                tooltip: 'Preview',
                color: theme.popupForeground.withValues(alpha: 0.55),
                onTap: () => sound.playNow(force: true),
              ),
            ],
          ),
        ),
        SettingsRow.field(
          SettingsCatalog.osdVolumeSoundVolume,
          control: ConfigValue<num>(
            store: store,
            path: const ['osd', 'volume_sound_volume'],
            fallback: kDefaultVolumeSoundVolume,
            builder: (context, value) => SettingsNumberField(
              value: value!,
              isInt: false,
              onChanged: (v) => store.set(
                ['osd', 'volume_sound_volume'],
                v.toDouble().clamp(0.0, 1.0),
              ),
            ),
          ),
        ),
        // The failure half: a missing file or an mpv that will not open it is
        // said here, and the preview above is the retry.
        ListenableBuilder(
          listenable: sound,
          builder: (context, _) {
            final error = sound.error;
            return error == null
                ? const SizedBox.shrink()
                : SettingsHint(error);
          },
        ),
      ],
    );
  }
}
