// Settings → Power: the machine's power mode, and the knobs beneath it.
//
// Two levels, because they answer two different people. **Power Mode** is the
// one choice most visits are for — Power Saver, Balanced, Performance — made
// through power-profiles-daemon (or TuneD's tuned-ppd), which moves every
// control the hardware has together and is allowed for the active session
// without a password. Where TuneD is the daemon, its whole catalogue follows.
//
// **Fine Tuning** is the rest: the firmware's platform profile, the CPU
// governor, the energy/performance preference, turbo boost and a frequency cap,
// each a sysfs file only root may write. Edits there are held until Apply and
// written in one `pkexec` batch, so a session of tweaking costs one password
// prompt rather than one per click — the Window Manager pane's "nothing is
// written until Save", for a different reason. They last until reboot, and the
// profile daemon rewrites the platform profile and energy preference whenever
// the mode changes; the section says both, since neither is visible otherwise.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/overlay/settings/settings_catalog.dart';
import 'package:moonswing/power_profile/power_profile_store.dart';
import 'package:moonswing/power_profile/power_profiles_client.dart';
import 'package:moonswing/power_profile/power_tuning.dart';
import 'package:moonswing/power_profile/tuned_client.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';

/// How wide the Fine Tuning dropdowns are, so they line up in one column.
const double _kKnobWidth = 220;

class PowerSettingsPage extends StatefulWidget {
  const PowerSettingsPage({super.key, PowerProfileStore? store})
    : _store = store;

  /// Injected by widget tests, so nothing here changes the power mode of the
  /// machine running them.
  final PowerProfileStore? _store;

  @override
  State<PowerSettingsPage> createState() => _PowerSettingsPageState();
}

class _PowerSettingsPageState extends State<PowerSettingsPage> {
  late final PowerProfileStore _store =
      widget._store ?? PowerProfileStore.instance;

  @override
  void initState() {
    super.initState();
    // Scoped like the keyboard page's lease: leaving the category disposes
    // the page.
    _store.acquire();
  }

  @override
  void dispose() {
    _store.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(theme),
          Container(height: 1, color: theme.divider),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _header(ThemeConfig theme) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
    child: Text(
      'Power',
      style: TextStyle(
        fontSize: ShellFontSizes.title,
        fontFamily: theme.fontFamily,
        color: theme.popupForeground,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _body(ThemeConfig theme) {
    if (_store.status == PowerProfilesStatus.loading &&
        _store.state == null &&
        _store.tuning == null) {
      return const Center(child: LoadingIndicator(size: 22));
    }
    final tuned = _store.tuned;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_store.error.isNotEmpty) ...[
            _banner(),
            const SizedBox(height: 16),
          ],
          if (_store.state != null) _modeSection(theme, _store.state!),
          if (tuned != null) ...[
            const SizedBox(height: 20),
            _tunedSection(theme, tuned),
          ],
          const SizedBox(height: 20),
          _tuningSection(theme),
        ],
      ),
    );
  }

  Widget _banner() {
    final unavailable =
        _store.errorKind == PowerProfilesFailureKind.unavailable;
    return SettingsBanner(
      title: unavailable
          ? 'Power modes unavailable'
          : 'Could not change the power mode',
      message: unavailable
          ? '${_store.error} Fine Tuning below works without it.'
          : _store.error,
      action: SettingsActionButton(
        label: 'Retry',
        compact: true,
        loading: _store.pendingProfile != null,
        onTap: _store.retry,
      ),
    );
  }

  // --- Power Mode -----------------------------------------------------------

  Widget _modeSection(ThemeConfig theme, PowerProfilesState state) {
    final active = state.profile(state.active);
    final pending = _store.pendingProfile;
    final batteryAware = state.batteryAware;
    final degraded = powerDegradedReason(state.degraded);
    return SettingsSection(
      label: 'Power Mode',
      info:
          'Applied by ${state.version.isEmpty ? 'the power profile daemon' : 'power-profiles-daemon ${state.version}'}, '
          'which moves every power control this machine has — the firmware '
          'profile, the CPU\'s energy preference, panel power savings — '
          'together. Lasts across reboots, and needs no password.',
      children: [
        SettingsRow.field(
          SettingsCatalog.powerMode,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final profile in state.profiles)
                      SettingsOptionButton(
                        label: powerProfileLabel(profile.profile),
                        selected: profile.profile == state.active,
                        onTap: () => _store.setProfile(profile.profile),
                      ),
                  ],
                ),
              ),
              if (pending != null) ...[
                const SizedBox(width: 10),
                const LoadingIndicator(size: 14),
              ],
            ],
          ),
        ),
        if (powerProfileDescription(state.active).isNotEmpty)
          SettingsHint(powerProfileDescription(state.active)),
        if (degraded.isNotEmpty) SettingsHint(degraded),
        if (active != null)
          SettingsRow(
            label: 'Applied through',
            info:
                'The daemon\'s drivers for this mode. "placeholder" means it '
                'found no power controls at all: the mode is remembered but '
                'changes nothing.',
            control: _readOnly(
              theme,
              active.isPlaceholder
                  ? 'Nothing — no power controls found'
                  : active.driverSummary,
            ),
          ),
        if (batteryAware != null)
          SettingsRow.field(
            SettingsCatalog.powerBatteryAware,
            control: _withPending(
              SettingsToggle(
                value: batteryAware,
                onChanged: _store.setBatteryAware,
              ),
              _store.pendingBatteryAware,
            ),
          ),
        if (state.holds.isNotEmpty) ...[
          const SizedBox(height: 4),
          const SettingsSubLabel(
            'Requested by applications',
            info:
                'Programs can ask for a mode while they run — a game for '
                'Performance, a battery monitor for Power Saver. Picking a '
                'mode yourself cancels every request.',
          ),
          for (final hold in state.holds) _holdRow(theme, hold),
        ],
        if (state.actions.isNotEmpty) ...[
          const SizedBox(height: 4),
          const SettingsSubLabel(
            'Also adjusted',
            info: 'Extra behaviours this daemon switches with the mode.',
          ),
          for (final action in state.actions) _actionRow(theme, action),
        ],
      ],
    );
  }

  Widget _holdRow(ThemeConfig theme, PowerProfileHold hold) {
    final app = hold.applicationId.isEmpty
        ? 'An application'
        : hold.applicationId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _readOnly(
        theme,
        '$app wants ${powerProfileLabel(hold.profile)}'
        '${hold.reason.isEmpty ? '' : ' — ${hold.reason}'}',
      ),
    );
  }

  Widget _actionRow(ThemeConfig theme, String action) {
    final description = powerActionDescription(action);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _readOnly(
        theme,
        description == null
            ? humanizeIdentifier(action)
            : '${humanizeIdentifier(action)} — $description',
      ),
    );
  }

  // --- TuneD ----------------------------------------------------------------

  Widget _tunedSection(ThemeConfig theme, TunedState tuned) {
    final pending = _store.pendingTuned;
    final known = tuned.profiles.any((p) => p.name == tuned.active);
    return SettingsSection(
      label: 'TuneD',
      info:
          'TuneD is this machine\'s profile daemon, and the power modes above '
          'are three of its profiles. Any of the others can be applied here; '
          'the choice lasts across reboots.',
      children: [
        SettingsRow.field(
          SettingsCatalog.powerTunedProfile,
          control: _withPending(
            SizedBox(
              width: 280,
              child: SettingsDropdown<String>(
                items: [
                  if (!known && tuned.active.isNotEmpty)
                    SettingsDropdownItem(
                      value: tuned.active,
                      label: tuned.active,
                    ),
                  for (final profile in tuned.profiles)
                    SettingsDropdownItem(
                      value: profile.name,
                      label: profile.name,
                      description: profile.summary.isEmpty
                          ? null
                          : profile.summary,
                    ),
                ],
                selected: tuned.active,
                onSelected: _store.switchTuned,
              ),
            ),
            pending != null && pending.isNotEmpty,
          ),
        ),
        SettingsRow(
          label: 'Chosen by',
          control: tuned.automatic
              ? _readOnly(theme, 'TuneD, for this hardware')
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _readOnly(theme, 'You'),
                    const SizedBox(width: 12),
                    SettingsActionButton(
                      label: tuned.recommended.isEmpty
                          ? 'Let TuneD choose'
                          : 'Let TuneD choose (${tuned.recommended})',
                      compact: true,
                      loading: pending == '',
                      enabled: pending == null,
                      onTap: _store.useTunedRecommended,
                    ),
                  ],
                ),
        ),
        if (_store.tunedError.isNotEmpty) SettingsHint(_store.tunedError),
      ],
    );
  }

  // --- Fine Tuning ----------------------------------------------------------

  Widget _tuningSection(ThemeConfig theme) {
    final tuning = _store.tuning;
    return SettingsSection(
      label: 'Fine Tuning',
      info:
          'The kernel\'s own power controls, beneath the power mode. Changes '
          'are held until Apply, then written as administrator in one go. '
          'They last until the next reboot, and the power profile daemon '
          'rewrites the platform profile and energy preference whenever the '
          'mode changes.',
      trailing: SettingsRescanButton(
        label: 'Refresh',
        onTap: _store.refreshTuning,
      ),
      children: [
        if (tuning == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: LoadingIndicator(size: 18)),
          )
        else if (tuning.isEmpty)
          const SettingsHint(
            'This machine exposes none of the kernel\'s power controls — no '
            'ACPI platform profile and no cpufreq policies.',
          )
        else
          ..._knobRows(theme, tuning),
      ],
    );
  }

  List<Widget> _knobRows(ThemeConfig theme, PowerTuning tuning) {
    final edits = _store.edits;
    final platform = tuning.platformProfile;
    final governor = tuning.governor;
    final epp = tuning.energyPreference;
    final boost = tuning.boost;
    final freq = tuning.maxFrequency;
    final driverLine = tuning.cpuDriver.isEmpty
        ? null
        : '${tuning.cpuDriver} · ${tuning.policyCount} '
              '${tuning.policyCount == 1 ? 'policy' : 'policies'}';
    return [
      if (driverLine != null)
        SettingsRow(label: 'CPU driver', control: _readOnly(theme, driverLine)),
      if (platform != null)
        SettingsRow.field(
          SettingsCatalog.powerPlatformProfile,
          control: _choiceKnob(
            platform,
            edits.platformProfile,
            _store.setPlatformProfile,
            describe: platformProfileDescription,
          ),
        ),
      if (governor != null)
        SettingsRow.field(
          SettingsCatalog.powerGovernor,
          info: _hardwareManaged(tuning.cpuDriver)
              ? '${SettingsCatalog.powerGovernor.description} Under '
                    '${tuning.cpuDriver} "powersave" is not slow: the CPU '
                    'chooses its own speed, steered by the energy preference.'
              : null,
          control: _choiceKnob(
            governor,
            edits.governor,
            _store.setGovernor,
            describe: governorDescription,
          ),
        ),
      if (epp != null)
        SettingsRow.field(
          SettingsCatalog.powerEnergyPreference,
          control: _choiceKnob(
            epp,
            edits.energyPreference,
            _store.setEnergyPreference,
            describe: energyPreferenceDescription,
          ),
        ),
      if (boost != null)
        SettingsRow.field(
          SettingsCatalog.powerBoost,
          control: _changed(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SettingsToggle(
                  value: edits.boost ?? boost.enabled ?? false,
                  onChanged: _store.setBoost,
                ),
                if (boost.enabled == null && edits.boost == null) ...[
                  const SizedBox(width: 8),
                  _readOnly(theme, 'Mixed'),
                ],
              ],
            ),
            edits.boost != null,
          ),
        ),
      if (freq != null)
        SettingsRow.field(
          SettingsCatalog.powerMaxFrequency,
          control: _changed(
            SizedBox(
              width: _kKnobWidth,
              child: SettingsDropdown<int>(
                items: [
                  for (final percent in frequencySteps(freq))
                    SettingsDropdownItem(
                      value: percent,
                      label: '$percent%',
                      detail: formatFrequency(freq.peakMhz * percent ~/ 100),
                    ),
                ],
                selected: edits.maxFrequencyPercent ?? freq.percent,
                onSelected: _store.setMaxFrequencyPercent,
              ),
            ),
            edits.maxFrequencyPercent != null,
          ),
        ),
      if (!edits.isEmpty || _store.applying || _store.tuningError != null) ...[
        const SizedBox(height: 8),
        _applyBar(theme, edits),
      ],
    ];
  }

  Widget _choiceKnob(
    ChoiceKnob knob,
    String? edit,
    ValueChanged<String> onSelected, {
    required String? Function(String value) describe,
  }) {
    return _changed(
      SizedBox(
        width: _kKnobWidth,
        child: SettingsDropdown<String>(
          items: [
            for (final choice in knob.choices)
              SettingsDropdownItem(
                value: choice,
                label: humanizeIdentifier(choice),
                description: describe(choice),
              ),
          ],
          // Null shows the dropdown's em dash, which is what "the cores
          // disagree" looks like until the user picks one value for all.
          selected: edit ?? knob.value,
          onSelected: onSelected,
        ),
      ),
      edit != null,
    );
  }

  Widget _applyBar(ThemeConfig theme, PowerTuningEdits edits) {
    final error = _store.tuningError;
    final count = edits.count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          SettingsBanner(
            title: error.kind == SysfsWriteFailureKind.rejected
                ? 'Some changes were refused'
                : 'Nothing was changed',
            message: error.message,
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Text(
                count == 0
                    ? ''
                    : '$count ${count == 1 ? 'change' : 'changes'} not '
                          'applied yet. Applying asks for the administrator '
                          'password.',
                style: TextStyle(
                  fontSize: ShellFontSizes.secondary,
                  fontFamily: theme.fontFamily,
                  color: theme.popupForeground.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SettingsActionButton(
              label: 'Discard',
              compact: true,
              enabled: !_store.applying,
              onTap: _store.discardTuning,
            ),
            const SizedBox(width: 8),
            SettingsActionButton(
              label: 'Apply',
              icon: FontAwesomeIcons.lock,
              compact: true,
              primary: true,
              loading: _store.applying,
              enabled: count > 0,
              onTap: _store.applyTuning,
            ),
          ],
        ),
      ],
    );
  }

  /// [control] with a "Changed" badge after it while its edit is unapplied.
  Widget _changed(Widget control, bool changed) {
    if (!changed) return control;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: control),
        const SizedBox(width: 8),
        const SettingsBadge('Changed'),
      ],
    );
  }

  Widget _withPending(Widget control, bool pending) {
    if (!pending) return control;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: control),
        const SizedBox(width: 10),
        const LoadingIndicator(size: 14),
      ],
    );
  }

  // Beside its label like any other value, not pushed to the far edge.
  Widget _readOnly(ThemeConfig theme, String text) => Text(
    text,
    style: TextStyle(
      fontSize: ShellFontSizes.secondary,
      fontFamily: theme.fontFamily,
      color: theme.popupForeground.withValues(alpha: 0.75),
    ),
  );
}

/// Whether [driver] lets the hardware pick frequencies itself, which is what
/// makes its `powersave` governor a misnomer.
bool _hardwareManaged(String driver) =>
    driver == 'intel_pstate' || driver.startsWith('amd-pstate');

/// The cap percentages offered: every tenth from 100 down to what the slowest
/// policy can go to, the floor itself, and whatever the machine holds now.
List<int> frequencySteps(FrequencyKnob knob) {
  final floor = knob.minPercent;
  final steps = <int>{
    for (var p = 100; p >= floor; p -= 10) p,
    floor,
    if (knob.percent != null) knob.percent!,
  }.toList()..sort((a, b) => b.compareTo(a));
  return steps;
}

/// `3600` → `3.6 GHz`; `800` → `800 MHz`.
String formatFrequency(int mhz) {
  if (mhz < 1000) return '$mhz MHz';
  final ghz = mhz / 1000;
  return '${ghz.toStringAsFixed(ghz >= 10 ? 0 : 1)} GHz';
}

/// One line on an ACPI platform profile choice, or null for a vendor's own.
String? platformProfileDescription(String value) => switch (value) {
  'low-power' => 'Lowest power draw; the machine runs slowest.',
  'cool' => 'Keeps the chassis cool to the touch.',
  'quiet' => 'Keeps the fans quiet, giving up some speed.',
  'balanced' => 'The firmware\'s everyday curve.',
  'balanced-performance' => 'Leans towards speed over battery.',
  'performance' => 'Highest power limits and the fans to match.',
  'max-power' => 'Beyond performance; loud and hungry.',
  'custom' => 'Set by a vendor tool rather than one of the above.',
  _ => null,
};

/// One line on a cpufreq governor, or null for one this table does not know.
String? governorDescription(String value) => switch (value) {
  'performance' => 'Always the highest frequency.',
  'powersave' =>
    'The lowest frequency, unless the driver manages speed itself.',
  'schedutil' => 'Follows the scheduler\'s view of how busy each core is.',
  'ondemand' => 'Jumps to full speed under load, drops back when idle.',
  'conservative' => 'Like ondemand, but steps up and down gradually.',
  'userspace' => 'Leaves the frequency to a program to set.',
  _ => null,
};

/// One line on an energy/performance preference value.
String? energyPreferenceDescription(String value) => switch (value) {
  'default' => 'Whatever the firmware set at boot.',
  'performance' => 'Speed first, whatever it costs.',
  'balance_performance' => 'Leans towards speed.',
  'balance_power' => 'Leans towards saving power.',
  'power' => 'Saving power first.',
  _ => null,
};
