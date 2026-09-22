// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/widgets.dart';
import 'package:moonswing/pulse_client.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/audio/pulse_helpers.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';

// ---------------------------------------------------------------------------
// Tab 4 — Device Profiles
// ---------------------------------------------------------------------------

class ProfilesTab extends StatefulWidget {
  const ProfilesTab({super.key, required this.client});

  final PulseClient client;

  @override
  _ProfilesTabState createState() => _ProfilesTabState();
}

class _ProfilesTabState extends State<ProfilesTab> {
  List<PaCard>? _cards;
  String _defaultSinkName = '';
  bool _monoEnabled = false;
  bool _loading = true;
  String? _error;
  bool _togglingMono = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards = await widget.client.getCardList();
      final monoLoaded =
          await isModuleLoaded(widget.client, 'module-remap-sink');
      final serverInfo = await widget.client.getServerInfo();
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _monoEnabled = monoLoaded;
        _defaultSinkName = serverInfo.defaultSinkName;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _setProfile(PaCard card, String profileName) async {
    try {
      await widget.client.setCardProfile(card.name, profileName);
      await _load();
    } catch (_) {}
  }

  Future<void> _toggleMono() async {
    if (_togglingMono) return;
    setState(() => _togglingMono = true);
    try {
      if (_monoEnabled) {
        final idx = await findModuleIndex(widget.client, 'module-remap-sink');
        if (idx != null) await widget.client.unloadModule(idx);
        if (_defaultSinkName.isNotEmpty) {
          await widget.client.setDefaultSink(_defaultSinkName);
        }
      } else {
        await widget.client.loadModule(
          'module-remap-sink',
          'sink_name=mono_mix'
              ' master=$_defaultSinkName'
              ' channels=1'
              ' channel_map=mono',
        );
        await widget.client.setDefaultSink('mono_mix');
      }
      final enabled = await isModuleLoaded(widget.client, 'module-remap-sink');
      if (mounted) setState(() => _monoEnabled = enabled);
    } catch (_) {}
    if (mounted) setState(() => _togglingMono = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (_error != null) return _buildRetry(theme, _error!);
    if (_loading) return const Center(child: LoadingIndicator(size: 22));
    return _buildContent(theme);
  }

  Widget _buildRetry(ThemeConfig theme, String error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(error,
              style: TextStyle(fontSize: 13, color: theme.accentText),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          SizedBox(
            width: 100,
            child: SettingsActionButton(
              label: 'Retry',
              onTap: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeConfig theme) {
    final cards = _cards!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: cards.isEmpty
              ? Center(
                  child: Text(
                    'No audio devices found',
                    style: TextStyle(
                        fontSize: 14,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.5)),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ProfileCard(
                    card: cards[i],
                    onProfileSelected: (p) => _setProfile(cards[i], p),
                  ),
                ),
        ),
        Container(height: 1, color: theme.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Mono Audio',
                      style: TextStyle(
                          fontSize: 13,
                          fontFamily: theme.fontFamily,
                          color: theme.popupForeground),
                    ),
                    Text(
                      'Mix all channels to a single channel',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: theme.fontFamily,
                          color: theme.muted),
                    ),
                  ],
                ),
              ),
              _togglingMono
                  ? const LoadingIndicator(size: 18)
                  : SettingsToggle(
                      value: _monoEnabled,
                      onChanged: (_) => _toggleMono(),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.card, required this.onProfileSelected});

  final PaCard card;
  final ValueChanged<String> onProfileSelected;

  @override
  _ProfileCardState createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  late String _activeProfile;

  @override
  void initState() {
    super.initState();
    _activeProfile = widget.card.activeProfileName;
  }

  @override
  void didUpdateWidget(_ProfileCard old) {
    super.didUpdateWidget(old);
    if (old.card.activeProfileName != widget.card.activeProfileName) {
      _activeProfile = widget.card.activeProfileName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final availableProfiles =
        widget.card.profiles.where((p) => p.available).toList();
    final profileItems = availableProfiles
        .map((p) => SettingsDropdownItem<String>(value: p.name, label: p.description))
        .toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.card.description,
                  style: TextStyle(
                      fontSize: 13,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  widget.card.name,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: theme.fontFamily,
                      color: theme.muted),
                ),
              ],
            ),
          ),
          Container(height: 1, color: theme.divider),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Profile',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 6),
                if (profileItems.isEmpty)
                  Text(
                    'No profiles available',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.muted),
                  )
                else
                  SettingsDropdown<String>(
                    items: profileItems,
                    selected: _activeProfile,
                    onSelected: (p) {
                      setState(() => _activeProfile = p);
                      widget.onProfileSelected(p);
                    },
                  ),
                if (widget.card.isBluez) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Bluetooth Codec',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Codec selection is managed by PipeWire/WirePlumber',
                    style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
