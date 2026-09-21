// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/loading_indicator.dart';
import 'package:graceful_shell/modules/network.dart';
import 'package:graceful_shell/overlay/settings/controls.dart';
import 'package:graceful_shell/theme/tokens.dart';
import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';

// ---------------------------------------------------------------------------
// Settings page — shared helper widgets
// ---------------------------------------------------------------------------

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  _PasswordFieldState createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.popupBackground,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: _focused ? theme.accent : theme.divider,
          width: 1,
        ),
      ),
      child: EditableText(
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: TextStyle(
          fontSize: 14,
          color: theme.popupForeground,
          fontFamily: theme.fontFamily,
        ),
        cursorColor: theme.accentText,
        backgroundCursorColor: theme.divider,
        obscureText: true,
        autofocus: true,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

class _NetworkListItem extends StatelessWidget {
  const _NetworkListItem({
    required this.network,
    required this.onTap,
  });

  final AvailableNetwork network;
  final VoidCallback onTap;


  FaIconData _icon() {
    return network.type == NetworkType.ethernet
        ? FontAwesomeIcons.ethernet
        : FontAwesomeIcons.wifi;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final n = network;
    final canTap = !n.isConnected;

    return HoverRegion(
      enabled: canTap,
      onTap: onTap,
      builder: (context, hovered) => Container(
        color: hovered && canTap ? theme.surfaceHover : null,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: Row(
          children: [
            FaIcon(
              _icon(),
              size: 14,
              color: theme.popupForeground.withValues(
                alpha:
                    n.type == NetworkType.wifi && n.signal < 30 ? 0.4 : 1.0,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    n.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: theme.fontFamily,
                      color: theme.popupForeground,
                    ),
                  ),
                  if (n.type == NetworkType.wifi)
                    Text(
                      '${n.signal}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (n.isConnected)
              const SettingsBadge('Connected')
            else if (n.secured)
              FaIcon(
                FontAwesomeIcons.lock,
                size: 11,
                color: theme.popupForeground.withValues(alpha: 0.5),
              ),
          ],
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Settings page — NetworkSettingsPage
// ---------------------------------------------------------------------------

class NetworkSettingsPage extends StatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  _NetworkSettingsPageState createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  List<AvailableNetwork>? _networks;
  String? _scanError;

  AvailableNetwork? _connecting;
  bool _isConnecting = false;
  String? _connectError;

  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    // Re-entered from async continuations (a connect finishing), so the
    // State may be gone by the time this runs.
    if (!mounted) return;
    setState(() {
      _networks = null;
      _scanError = null;
    });
    try {
      final networks = await scanNetworks();
      if (mounted) setState(() => _networks = networks);
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    }
  }

  Future<void> _connect(AvailableNetwork network, String? password) async {
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });
    try {
      await connectToNetwork(network: network, password: password);
      if (mounted) {
        setState(() {
          _connecting = null;
          _isConnecting = false;
        });
        _passwordController.clear();
        _scan();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectError = e.toString();
        });
      }
    }
  }

  void _doConnect() {
    if (_isConnecting || _connecting == null) return;
    final pw = _connecting!.secured ? _passwordController.text.trim() : null;
    _connect(_connecting!, pw);
  }

  void _cancelConnect() {
    setState(() {
      _connecting = null;
      _connectError = null;
    });
    _passwordController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_connecting != null) return _buildConnectForm(context);
    return _buildNetworkList(context);
  }

  Widget _buildNetworkList(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Networks',
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SettingsRescanButton(onTap: _scan),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(child: _buildListBody(theme)),
      ],
    );
  }

  Widget _buildListBody(ThemeConfig theme) {
    if (_scanError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _scanError!,
              style: TextStyle(
                fontSize: 13,
                fontFamily: theme.fontFamily,
                color: theme.accentText,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SettingsRescanButton(onTap: _scan, label: 'Retry'),
          ],
        ),
      );
    }
    if (_networks == null) {
      return const Center(child: LoadingIndicator(size: 22));
    }
    if (_networks!.isEmpty) {
      return Center(
        child: Text(
          'No networks found',
          style: TextStyle(
            fontSize: 14,
            fontFamily: theme.fontFamily,
            color: theme.popupForeground.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _networks!.length,
      itemBuilder: (_, i) {
        final n = _networks![i];
        return _NetworkListItem(
          network: n,
          onTap: () => setState(() {
            _connecting = n;
            _connectError = null;
            _passwordController.clear();
          }),
        );
      },
    );
  }

  Widget _buildConnectForm(BuildContext context) {
    final theme = ThemeScope.of(context);
    final n = _connecting!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
          child: Row(
            children: [
              SettingsIconButton(
                icon: FontAwesomeIcons.arrowLeft,
                size: ShellFontSizes.label,
                color: theme.popupForeground,
                onTap: _cancelConnect,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  n.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontFamily: theme.fontFamily,
                    color: theme.popupForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: theme.divider),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (n.secured) ...[
                    Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: theme.fontFamily,
                        color: theme.popupForeground.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _PasswordField(
                      controller: _passwordController,
                      focusNode: _passwordFocusNode,
                      onSubmitted: (_) => _doConnect(),
                    ),
                    const SizedBox(height: 16),
                  ] else
                    const SizedBox(height: 16),
                  if (_connectError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _connectError!,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: theme.fontFamily,
                          color: theme.accentText,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: SettingsActionButton(
                          label: 'Connect',
                          onTap: _doConnect,
                          primary: true,
                          loading: _isConnecting,
                          enabled: !_isConnecting,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SettingsActionButton(
                          label: 'Cancel',
                          onTap: _cancelConnect,
                          enabled: !_isConnecting,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
