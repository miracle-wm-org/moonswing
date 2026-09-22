// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/widgets.dart';
import 'package:moonswing/pulse_client.dart';
import 'package:moonswing/config.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/settings/audio/advanced_tab.dart';
import 'package:moonswing/overlay/settings/audio/apps_tab.dart';
import 'package:moonswing/overlay/settings/audio/input_tab.dart';
import 'package:moonswing/overlay/settings/audio/output_tab.dart';
import 'package:moonswing/overlay/settings/audio/profiles_tab.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/underline_tabs.dart';

// ---------------------------------------------------------------------------
// AudioSettingsPage
// ---------------------------------------------------------------------------

class AudioSettingsPage extends StatefulWidget {
  const AudioSettingsPage({super.key});

  @override
  _AudioSettingsPageState createState() => _AudioSettingsPageState();
}

class _AudioSettingsPageState extends State<AudioSettingsPage> {
  PulseClient? _client;
  bool _clientReady = false;
  String? _initError;
  int _selectedTab = 0;

  static const _tabs = ['Output', 'Input', 'Apps', 'Profiles', 'Advanced'];

  @override
  void initState() {
    super.initState();
    _initClient();
  }

  Future<void> _initClient() async {
    try {
      final client = PulseClient();
      await client.initialize();
      if (!mounted) return;
      setState(() {
        _client = client;
        _clientReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = 'PulseAudio unavailable: $e');
    }
  }

  @override
  void dispose() {
    // PulseClient is a singleton — do not dispose here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    if (_initError != null) return _buildError(theme);
    if (!_clientReady) return _buildLoading(theme);
    return _buildLoaded(theme);
  }

  Widget _buildHeader(ThemeConfig theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      child: Text(
        'Audio',
        style: TextStyle(
          fontSize: 16,
          fontFamily: theme.fontFamily,
          color: theme.popupForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        const Expanded(child: Center(child: LoadingIndicator(size: 22))),
      ],
    );
  }

  Widget _buildError(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: Center(
            child: Text(
              _initError!,
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: theme.fontFamily,
                  color: theme.accentText),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoaded(ThemeConfig theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(theme),
        Container(height: 1, color: theme.divider),
        SizedBox(
          height: 40,
          child: Row(
            // Stretch so each tab's underline sits on the divider below the
            // strip rather than floating at the tab's intrinsic height.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < _tabs.length; i++)
                UnderlineTab(
                  label: _tabs[i],
                  selected: i == _selectedTab,
                  fontSize: 13,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onTap: () => setState(() => _selectedTab = i),
                ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(child: _buildTabContent()),
      ],
    );
  }

  Widget _buildTabContent() {
    final client = _client!;
    switch (_selectedTab) {
      case 0:
        return OutputTab(client: client);
      case 1:
        return InputTab(client: client);
      case 2:
        return AppsTab(client: client);
      case 3:
        return ProfilesTab(client: client);
      case 4:
        return const AdvancedTab();
      default:
        return const SizedBox.shrink();
    }
  }
}
