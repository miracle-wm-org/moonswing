// Settings › Network › VPN: the profiles NetworkManager keeps, a switch on
// each, and the forms that add one.
//
// The list is a [SettingsList] like every edited collection — a remove icon on
// each row, the adder as its last row — without numbers or grips, since
// NetworkManager's profiles have no order. Adding opens a form in the page's
// place (the way joining a Wi-Fi network does): OpenVPN, PPTP and WireGuard
// each have one, and Import reads a file through the plugin that understands
// it and shows what it made before anything is saved.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:moonswing/emoji/emoji_clipboard.dart';
import 'package:moonswing/icons/shell_glyph.dart';
import 'package:moonswing/icons/shell_icon.dart';
import 'package:moonswing/loading_indicator.dart';
import 'package:moonswing/overlay/file_picker.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/theme_config.dart';
import 'package:moonswing/theme/tokens.dart';
import 'package:moonswing/vpn/libnm_import.dart';
import 'package:moonswing/vpn/nm_vpn_client.dart';
import 'package:moonswing/vpn/vpn_model.dart';
import 'package:moonswing/vpn/vpn_plugins.dart';
import 'package:moonswing/vpn/vpn_spec.dart';
import 'package:moonswing/vpn/vpn_store.dart';
import 'package:moonswing/vpn/x25519.dart';

/// What the network page shows in place of its lists.
sealed class VpnFormRequest {
  const VpnFormRequest();
}

/// A blank form for a new profile of [kind].
class VpnAddRequest extends VpnFormRequest {
  const VpnAddRequest(this.kind);

  final VpnKind kind;
}

/// A file that was read, for the user to look over and save.
class VpnImportRequest extends VpnFormRequest {
  const VpnImportRequest(this.draft);

  final VpnImportDraft draft;
}

/// A password for a profile whose sign-in failed.
class VpnPasswordRequest extends VpnFormRequest {
  const VpnPasswordRequest(this.profile);

  final VpnProfile profile;
}

/// Picks one file, as the page's file picker does. Injected by tests.
typedef VpnFilePicker = Future<String?> Function(BuildContext context);

/// Configuration files the installed plugins and the WireGuard reader take.
final FilePickerFilter kVpnFileFilter = FilePickerFilter(
  label: 'VPN configurations',
  extensions: const {'.ovpn', '.conf', '.pcf', '.cfg', '.vpn'},
);

Future<String?> _pickVpnFile(BuildContext context) async {
  final paths = await showFilePicker(
    context,
    filters: [kVpnFileFilter, FilePickerFilter.all],
    allowMultiple: false,
  );
  return paths == null || paths.isEmpty ? null : paths.first;
}

enum _AddChoice {
  openvpn('OpenVPN', VpnKind.openvpn),
  pptp('PPTP', VpnKind.pptp),
  wireguard('WireGuard', VpnKind.wireguard),
  import('Import from file…', null);

  const _AddChoice(this.label, this.kind);

  final String label;
  final VpnKind? kind;
}

// ---------------------------------------------------------------------------
// The section
// ---------------------------------------------------------------------------

/// The VPN section of the network page. Holds no lease itself — the page does.
class VpnSection extends StatefulWidget {
  const VpnSection({
    super.key,
    required this.store,
    required this.onOpen,
    this.pickFile,
  });

  final VpnStore store;
  final ValueChanged<VpnFormRequest> onOpen;
  final VpnFilePicker? pickFile;

  @override
  State<VpnSection> createState() => _VpnSectionState();
}

class _VpnSectionState extends State<VpnSection> {
  VpnStore get _store => widget.store;

  bool _importing = false;
  String _importError = '';

  Future<void> _choose(_AddChoice choice) async {
    final kind = choice.kind;
    if (kind != null) {
      widget.onOpen(VpnAddRequest(kind));
      return;
    }
    final path = await (widget.pickFile ?? _pickVpnFile)(context);
    if (path == null || !mounted) return;
    setState(() {
      _importing = true;
      _importError = '';
    });
    try {
      final draft = await _store.prepareImport(path);
      if (!mounted) return;
      setState(() => _importing = false);
      widget.onOpen(VpnImportRequest(draft));
    } on VpnImportException catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _importError = e.message;
        });
      }
    }
  }

  Future<void> _remove(VpnProfile profile) async {
    final confirmed = await showSettingsConfirm(
      context,
      title: 'Remove ${profile.name}?',
      message:
          'NetworkManager forgets the profile and anything saved in it. '
          'Certificate files it names stay where they are.',
      confirmLabel: 'Remove',
      warning: _store.stateOf(profile).on
          ? 'It is connected, and will be disconnected first.'
          : null,
    );
    if (confirmed) await _store.remove(profile);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) => SettingsSection(
        label: 'VPN',
        info:
            'The VPNs NetworkManager keeps — the same list nmcli and other '
            'desktops show. Turning one on routes this machine through it; '
            'passwords and keys are saved by NetworkManager, readable only by '
            'root.',
        children: [
          if (_store.error.isNotEmpty) ...[
            SettingsBanner(
              title: _store.status == VpnStoreStatus.unavailable
                  ? 'VPNs unavailable'
                  : 'Could not read the VPNs',
              message: _store.error,
              action: SettingsActionButton(
                label: 'Retry',
                compact: true,
                onTap: _store.retry,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_importError.isNotEmpty) ...[
            SettingsNotice(
              title: 'Could not import',
              message: _importError,
              icon: ShellGlyph.warning,
              onDismiss: () => setState(() => _importError = ''),
            ),
            const SizedBox(height: 8),
          ],
          if (_store.status == VpnStoreStatus.loading &&
              _store.profiles.isEmpty)
            const SizedBox(
              height: kSettingsListRowHeight,
              child: Center(child: LoadingIndicator(size: 16)),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _list(context),
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final profiles = _store.profiles;
    final theme = ThemeScope.of(context);
    return SettingsList(
      itemCount: profiles.length,
      numbered: false,
      emptyText: 'No VPNs yet',
      removeTooltip: 'Remove VPN',
      itemKey: (i) => ValueKey(profiles[i].path),
      iconBuilder: (context, i) => ShellIcon(
        profiles[i].kind == VpnKind.wireguard
            ? ShellGlyph.key
            : ShellGlyph.lock,
        size: ShellFontSizes.secondary,
        color: theme.popupForeground.withValues(alpha: 0.7),
      ),
      itemBuilder: (context, i) => _VpnRowText(
        profile: profiles[i],
        state: _store.stateOf(profiles[i]),
        error: _store.errorOf(profiles[i]),
        removing: _store.pendingOf(profiles[i]) == VpnPending.removing,
      ),
      trailingBuilder: (context, i) => _trailing(profiles[i]),
      onRemove: (i) => _remove(profiles[i]),
      adder: _importing
          ? const SizedBox(
              height: kSettingsListRowHeight,
              child: Center(child: LoadingIndicator(size: 14)),
            )
          : SettingsListAddDropdown<_AddChoice>(
              label: 'Add VPN',
              options: _AddChoice.values,
              labelOf: (c) => c.label,
              detailOf: (c) {
                final kind = c.kind;
                if (kind == null || kind == VpnKind.wireguard) return null;
                return _store.pluginFor(kind) == null
                    ? 'plugin not installed'
                    : null;
              },
              iconOf: (c) => ShellIcon(
                c.kind == null ? ShellGlyph.file : ShellGlyph.add,
                size: ShellFontSizes.caption,
                color: theme.popupForeground.withValues(alpha: 0.7),
              ),
              onSelected: _choose,
            ),
    );
  }

  Widget _trailing(VpnProfile profile) {
    final state = _store.stateOf(profile);
    final pending = _store.pendingOf(profile);
    final error = _store.errorOf(profile);
    final busy =
        state == VpnState.connecting || state == VpnState.disconnecting;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null && error.wantsPassword && profile.takesPassword) ...[
          SettingsActionButton(
            label: 'Password…',
            compact: true,
            onTap: () => widget.onOpen(VpnPasswordRequest(profile)),
          ),
          const SizedBox(width: 10),
        ],
        if (busy) ...[
          const LoadingIndicator(size: 14),
          const SizedBox(width: 10),
        ],
        Opacity(
          opacity: pending == null ? 1 : 0.5,
          child: SettingsToggle(
            value: state.on,
            onChanged: (on) => unawaited(_store.setEnabled(profile, on)),
          ),
        ),
      ],
    );
  }
}

class _VpnRowText extends StatelessWidget {
  const _VpnRowText({
    required this.profile,
    required this.state,
    required this.error,
    required this.removing,
  });

  final VpnProfile profile;
  final VpnState state;
  final VpnProfileError? error;
  final bool removing;

  String get _stateText => removing
      ? 'Removing…'
      : switch (state) {
          VpnState.connected => 'Connected',
          VpnState.connecting => 'Connecting…',
          VpnState.disconnecting => 'Disconnecting…',
          VpnState.disconnected => '',
        };

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final detail = [
      profile.kindLabel,
      if (profile.server.isNotEmpty) profile.server,
      if (_stateText.isNotEmpty) _stateText,
    ].join(' · ');
    final error = this.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.secondary,
              fontFamily: theme.fontFamily,
              color: theme.popupForeground,
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: ShellFontSizes.caption,
              fontFamily: theme.fontFamily,
              color: state == VpnState.connected
                  ? theme.accentText
                  : theme.popupForeground.withValues(alpha: 0.6),
            ),
          ),
          if (error != null)
            Text(
              error.message,
              style: TextStyle(
                fontSize: ShellFontSizes.caption,
                fontFamily: theme.fontFamily,
                color: kErrorColor,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The forms
// ---------------------------------------------------------------------------

/// The field column's width, so every form's fields line up.
const double _kFieldWidth = 340;

/// A form in the page's place: a back arrow and title, the fields, and Save.
class VpnFormPage extends StatelessWidget {
  const VpnFormPage({
    super.key,
    required this.store,
    required this.request,
    required this.onClose,
    this.pickFile,
  });

  final VpnStore store;
  final VpnFormRequest request;

  /// Back to the lists — on Cancel, and once a save has landed.
  final VoidCallback onClose;

  /// Picks a certificate or key for the OpenVPN form. Injected by tests.
  final VpnFilePicker? pickFile;

  String get _title => switch (request) {
    VpnAddRequest(:final kind) => 'Add ${kind.label} VPN',
    VpnImportRequest(:final draft) => 'Import ${_baseName(draft.path)}',
    VpnPasswordRequest(:final profile) => 'Sign in to ${profile.name}',
  };

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final body = switch (request) {
      VpnAddRequest(kind: VpnKind.openvpn) => _OpenVpnForm(
        store: store,
        onSaved: onClose,
        onCancel: onClose,
        pickFile: pickFile,
      ),
      VpnAddRequest(kind: VpnKind.pptp) => _PptpForm(
        store: store,
        onSaved: onClose,
        onCancel: onClose,
      ),
      VpnAddRequest() => _WireGuardForm(
        store: store,
        onSaved: onClose,
        onCancel: onClose,
      ),
      VpnImportRequest(:final draft) => _ImportForm(
        store: store,
        draft: draft,
        onSaved: onClose,
        onCancel: onClose,
      ),
      VpnPasswordRequest(:final profile) => _PasswordForm(
        store: store,
        profile: profile,
        onSaved: onClose,
        onCancel: onClose,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
          child: Row(
            children: [
              SettingsIconButton(
                icon: ShellGlyph.arrowLeft,
                size: ShellFontSizes.label,
                color: theme.popupForeground,
                tooltip: 'Back',
                onTap: onClose,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: ShellFontSizes.title,
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: body,
          ),
        ),
      ],
    );
  }
}

String _baseName(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// The shared half of every form: the error line, Save and Cancel, and the
/// save itself, which turns NetworkManager's refusal into that line.
mixin _VpnFormState<T extends StatefulWidget> on State<T> {
  bool saving = false;
  String error = '';

  /// Every controller the form owns, disposed with it and listened to so a
  /// keystroke clears a stale error.
  final List<TextEditingController> _controllers = [];

  TextEditingController controller([String text = '']) {
    final c = TextEditingController(text: text);
    c.addListener(_edited);
    _controllers.add(c);
    return c;
  }

  void _edited() {
    if (error.isNotEmpty && mounted) setState(() => error = '');
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  /// The first problem with what is typed, or null.
  String? validate();

  Future<void> commit();

  VoidCallback get onSaved;
  VoidCallback get onCancel;

  Future<void> save() async {
    if (saving) return;
    final problem = validate();
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      saving = true;
      error = '';
    });
    try {
      await commit();
      if (mounted) onSaved();
    } on VpnBackendException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on VpnImportException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget actions({String saveLabel = 'Save'}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ErrorText(error),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 140,
              child: SettingsActionButton(
                label: saveLabel,
                primary: true,
                loading: saving,
                enabled: !saving,
                onTap: save,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: SettingsActionButton(
                label: 'Cancel',
                enabled: !saving,
                onTap: onCancel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return Text(
      text,
      style: TextStyle(
        fontSize: ShellFontSizes.secondary,
        fontFamily: theme.fontFamily,
        color: kErrorColor,
      ),
    );
  }
}

/// A labelled text field at the forms' width.
Widget _field(
  String label,
  TextEditingController controller, {
  String? hint,
  String? info,
  bool obscure = false,
  bool autofocus = false,
  List<TextInputFormatter>? formatters,
  Widget? trailing,
  ValueChanged<String>? onSubmitted,
}) => SettingsRow(
  label: label,
  info: info,
  control: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SettingsTextField(
        controller: controller,
        width: _kFieldWidth,
        hint: hint,
        obscureText: obscure,
        autofocus: autofocus,
        inputFormatters: formatters,
        onChanged: (_) {},
        onSubmitted: onSubmitted,
      ),
      if (trailing != null) ...[const SizedBox(width: 8), trailing],
    ],
  ),
);

final List<TextInputFormatter> _digits = [
  FilteringTextInputFormatter.digitsOnly,
];

/// A banner for a form whose plugin is not installed: the profile can still be
/// saved, but NetworkManager will refuse to start it until it is.
Widget? _missingPlugin(VpnStore store, VpnKind kind) {
  if (store.pluginFor(kind) != null) return null;
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SettingsBanner(
      title: '${kind.label} plugin not installed',
      message:
          'NetworkManager needs ${vpnPluginPackage(kind)} to connect a '
          '${kind.label} VPN. The profile can be saved now and will connect '
          'once it is installed.',
      action: SettingsActionButton(
        label: 'Check again',
        compact: true,
        onTap: store.retry,
      ),
    ),
  );
}

// --- OpenVPN -----------------------------------------------------------------

class _OpenVpnForm extends StatefulWidget {
  const _OpenVpnForm({
    required this.store,
    required this.onSaved,
    required this.onCancel,
    this.pickFile,
  });

  final VpnStore store;
  final VoidCallback onSaved;
  final VoidCallback onCancel;
  final VpnFilePicker? pickFile;

  @override
  State<_OpenVpnForm> createState() => _OpenVpnFormState();
}

class _OpenVpnFormState extends State<_OpenVpnForm>
    with _VpnFormState<_OpenVpnForm> {
  late final _name = controller();
  late final _gateway = controller();
  late final _ca = controller();
  late final _cert = controller();
  late final _key = controller();
  late final _keyPassword = controller();
  late final _user = controller();
  late final _password = controller();
  OpenVpnAuth _auth = OpenVpnAuth.password;
  bool _tcp = false;

  @override
  VoidCallback get onSaved => widget.onSaved;
  @override
  VoidCallback get onCancel => widget.onCancel;

  OpenVpnSpec get _spec => OpenVpnSpec(
    name: _name.text,
    gateway: _gateway.text,
    auth: _auth,
    caCert: _ca.text,
    userCert: _cert.text,
    userKey: _key.text,
    keyPassword: _keyPassword.text,
    username: _user.text,
    password: _password.text,
    tcp: _tcp,
  );

  @override
  String? validate() => _spec.validate();

  @override
  Future<void> commit() {
    final spec = _spec;
    return widget.store.add((uuid) => spec.toSettings(uuid: uuid));
  }

  Future<void> _choose(TextEditingController target) async {
    final pick =
        widget.pickFile ??
        (context) async {
          final paths = await showFilePicker(
            context,
            filters: [
              const FilePickerFilter(
                label: 'Certificates and keys',
                extensions: {'.crt', '.pem', '.cer', '.key', '.p12', '.der'},
              ),
              FilePickerFilter.all,
            ],
            allowMultiple: false,
          );
          return paths == null || paths.isEmpty ? null : paths.first;
        };
    final path = await pick(context);
    if (path != null && mounted) target.text = path;
  }

  Widget _fileField(String label, TextEditingController c, {String? info}) =>
      _field(
        label,
        c,
        hint: '/path/to/file',
        info: info,
        trailing: SettingsActionButton(
          label: 'Choose…',
          compact: true,
          onTap: () => _choose(c),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final missing = _missingPlugin(widget.store, VpnKind.openvpn);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?missing,
        SettingsSection(
          label: 'Connection',
          children: [
            _field('Name', _name, hint: 'Office', autofocus: true),
            _field(
              'Gateway',
              _gateway,
              hint: 'vpn.example.com:1194',
              info:
                  'The server, with its port after a colon if it is not '
                  '1194. Several servers may be listed, separated by commas; '
                  'they are tried in turn.',
            ),
            SettingsRow(
              label: 'Use TCP',
              info:
                  'OpenVPN uses UDP unless the server says otherwise. Turn '
                  'this on for a server configured with "proto tcp".',
              control: SettingsToggle(
                value: _tcp,
                onChanged: (v) => setState(() => _tcp = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsSection(
          label: 'Authentication',
          children: [
            SettingsRow(
              label: 'Sign in with',
              control: SizedBox(
                width: _kFieldWidth,
                child: SettingsChoice<OpenVpnAuth>(
                  options: OpenVpnAuth.values,
                  value: _auth,
                  labelOf: (a) => a.label,
                  onChanged: (a) => setState(() => _auth = a),
                ),
              ),
            ),
            _fileField(
              'CA certificate',
              _ca,
              info:
                  'The certificate of the authority that signed the '
                  'server\'s — usually ca.crt. NetworkManager reads it from '
                  'here each time, so leave the file where it is.',
            ),
            if (_auth.usesCertificate) ...[
              _fileField('Your certificate', _cert),
              _fileField('Your private key', _key),
              _field(
                'Key password',
                _keyPassword,
                obscure: true,
                hint: 'If the key has one',
              ),
            ],
            if (_auth.usesPassword) ...[
              _field('User name', _user),
              _field(
                'Password',
                _password,
                obscure: true,
                onSubmitted: (_) {
                  save();
                },
              ),
            ],
          ],
        ),
        actions(),
      ],
    );
  }
}

// --- PPTP --------------------------------------------------------------------

class _PptpForm extends StatefulWidget {
  const _PptpForm({
    required this.store,
    required this.onSaved,
    required this.onCancel,
  });

  final VpnStore store;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_PptpForm> createState() => _PptpFormState();
}

class _PptpFormState extends State<_PptpForm> with _VpnFormState<_PptpForm> {
  late final _name = controller();
  late final _gateway = controller();
  late final _user = controller();
  late final _password = controller();
  late final _domain = controller();
  bool _mppe = true;

  @override
  VoidCallback get onSaved => widget.onSaved;
  @override
  VoidCallback get onCancel => widget.onCancel;

  PptpSpec get _spec => PptpSpec(
    name: _name.text,
    gateway: _gateway.text,
    username: _user.text,
    password: _password.text,
    domain: _domain.text,
    mppe: _mppe,
  );

  @override
  String? validate() => _spec.validate();

  @override
  Future<void> commit() {
    final spec = _spec;
    return widget.store.add((uuid) => spec.toSettings(uuid: uuid));
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missingPlugin(widget.store, VpnKind.pptp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?missing,
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SettingsNotice(
            title: 'PPTP is not secure',
            message:
                'Its encryption has been broken for years. Use it only for a '
                'server that offers nothing else.',
            icon: ShellGlyph.warning,
          ),
        ),
        SettingsSection(
          label: 'Connection',
          children: [
            _field('Name', _name, hint: 'Office', autofocus: true),
            _field('Gateway', _gateway, hint: 'vpn.example.com'),
            _field('User name', _user),
            _field(
              'Password',
              _password,
              obscure: true,
              onSubmitted: (_) {
                save();
              },
            ),
            _field(
              'NT domain',
              _domain,
              hint: 'Optional',
              info: 'Only for a Windows server that asks for one.',
            ),
            SettingsRow(
              label: 'Require encryption',
              info:
                  'MPPE. Without it the tunnel carries everything in the '
                  'clear; with it, only MS-CHAPv2 sign-in is allowed.',
              control: SettingsToggle(
                value: _mppe,
                onChanged: (v) => setState(() => _mppe = v),
              ),
            ),
          ],
        ),
        actions(),
      ],
    );
  }
}

// --- WireGuard ---------------------------------------------------------------

class _WireGuardForm extends StatefulWidget {
  const _WireGuardForm({
    required this.store,
    required this.onSaved,
    required this.onCancel,
  });

  final VpnStore store;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_WireGuardForm> createState() => _WireGuardFormState();
}

class _WireGuardFormState extends State<_WireGuardForm>
    with _VpnFormState<_WireGuardForm> {
  late final _name = controller();
  late final _privateKey = controller();
  late final _address = controller();
  late final _dns = controller();
  late final _listenPort = controller();
  late final _peerKey = controller();
  late final _presharedKey = controller();
  late final _endpoint = controller();
  late final _allowedIps = controller('0.0.0.0/0, ::/0');
  late final _keepalive = controller();

  /// The public key of what is in the private key field, or null.
  String? _publicKey;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _privateKey.addListener(_derivePublicKey);
  }

  void _derivePublicKey() {
    final next = wireGuardPublicKey(_privateKey.text);
    if (next != _publicKey) {
      setState(() {
        _publicKey = next;
        _copied = false;
      });
    }
  }

  @override
  VoidCallback get onSaved => widget.onSaved;
  @override
  VoidCallback get onCancel => widget.onCancel;

  int? _number(TextEditingController c) => int.tryParse(c.text.trim());

  WireGuardSpec get _spec => WireGuardSpec(
    name: _name.text,
    interfaceName: wireGuardInterfaceFor(
      _name.text,
      widget.store.takenInterfaces,
    ),
    privateKey: _privateKey.text,
    addresses: splitWireGuardList(_address.text),
    dns: splitWireGuardList(_dns.text),
    listenPort: _number(_listenPort),
    peers: [
      WireGuardPeerSpec(
        publicKey: _peerKey.text,
        presharedKey: _presharedKey.text,
        endpoint: _endpoint.text,
        allowedIps: splitWireGuardList(_allowedIps.text),
        persistentKeepalive: _number(_keepalive),
      ),
    ],
  );

  @override
  String? validate() {
    final problem = _spec.validate();
    if (problem != null) return problem;
    if (_endpoint.text.trim().isEmpty) {
      return 'Enter the server\'s endpoint, such as vpn.example.com:51820.';
    }
    return null;
  }

  @override
  Future<void> commit() {
    final spec = _spec;
    return widget.store.add((uuid) => spec.toSettings(uuid: uuid));
  }

  Future<void> _copy() async {
    final key = _publicKey;
    if (key == null) return;
    final result = await copyTextToClipboard(key);
    if (mounted) setState(() => _copied = result == ClipboardResult.copied);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final publicKey = _publicKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          label: 'This machine',
          children: [
            _field('Name', _name, hint: 'Home', autofocus: true),
            _field(
              'Private key',
              _privateKey,
              obscure: true,
              info:
                  'This machine\'s half of the tunnel\'s keys. Generate one '
                  'and give the server its public key, or paste the private '
                  'key the server\'s administrator sent you.',
              trailing: SettingsActionButton(
                label: 'Generate',
                compact: true,
                onTap: () => _privateKey.text = generateWireGuardPrivateKey(),
              ),
            ),
            SettingsRow(
              label: 'Public key',
              info: 'What the server needs to know this machine by.',
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: _kFieldWidth,
                    child: publicKey == null
                        ? _dim(theme, 'Appears once the private key is valid')
                        : Text(
                            publicKey,
                            style: TextStyle(
                              fontSize: ShellFontSizes.secondary,
                              fontFamily: 'monospace',
                              color: theme.popupForeground,
                            ),
                          ),
                  ),
                  if (publicKey != null) ...[
                    const SizedBox(width: 8),
                    SettingsIconButton(
                      icon: _copied ? ShellGlyph.check : ShellGlyph.copy,
                      tooltip: 'Copy',
                      color: theme.popupForeground,
                      onTap: _copy,
                    ),
                  ],
                ],
              ),
            ),
            _field(
              'Address',
              _address,
              hint: '10.0.0.2/32',
              info:
                  'This machine\'s address inside the tunnel. Several may be '
                  'given, separated by commas — one IPv4 and one IPv6 is '
                  'common.',
            ),
            _field(
              'DNS',
              _dns,
              hint: 'Optional — 10.0.0.1',
              info:
                  'Name servers to use while the tunnel is up, separated by '
                  'commas. Anything that is not an address is a search '
                  'domain. When the tunnel carries everything, every lookup '
                  'goes to these.',
            ),
            _field(
              'Listen port',
              _listenPort,
              hint: 'Optional — any free port',
              formatters: _digits,
            ),
          ],
        ),
        const SizedBox(height: 20),
        SettingsSection(
          label: 'Server',
          children: [
            _field('Public key', _peerKey, hint: 'The server\'s public key'),
            _field('Endpoint', _endpoint, hint: 'vpn.example.com:51820'),
            _field(
              'Allowed IPs',
              _allowedIps,
              info:
                  'Which addresses go through the tunnel. 0.0.0.0/0, ::/0 '
                  'sends everything; a narrower range, such as 10.0.0.0/24, '
                  'sends only the server\'s network.',
            ),
            _field(
              'Preshared key',
              _presharedKey,
              obscure: true,
              hint: 'Optional',
            ),
            _field(
              'Keepalive',
              _keepalive,
              hint: 'Optional — seconds, such as 25',
              formatters: _digits,
              info:
                  'Sends a packet this often so a router between here and '
                  'the server keeps the tunnel open. Needed behind most NATs.',
            ),
          ],
        ),
        actions(),
      ],
    );
  }
}

Widget _dim(ThemeConfig theme, String text) => Text(
  text,
  style: TextStyle(
    fontSize: ShellFontSizes.secondary,
    fontFamily: theme.fontFamily,
    color: theme.popupForeground.withValues(alpha: 0.5),
  ),
);

Widget _readOnly(ThemeConfig theme, String text) => SizedBox(
  width: _kFieldWidth,
  child: Text(
    text,
    style: TextStyle(
      fontSize: ShellFontSizes.secondary,
      fontFamily: theme.fontFamily,
      color: theme.popupForeground,
    ),
  ),
);

// --- Import ------------------------------------------------------------------

class _ImportForm extends StatefulWidget {
  const _ImportForm({
    required this.store,
    required this.draft,
    required this.onSaved,
    required this.onCancel,
  });

  final VpnStore store;
  final VpnImportDraft draft;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_ImportForm> createState() => _ImportFormState();
}

class _ImportFormState extends State<_ImportForm>
    with _VpnFormState<_ImportForm> {
  late final _name = controller(widget.draft.profile.name);
  late final _user = controller(widget.draft.username);
  late final _password = controller();

  @override
  VoidCallback get onSaved => widget.onSaved;
  @override
  VoidCallback get onCancel => widget.onCancel;

  @override
  String? validate() => validateVpnName(_name.text);

  @override
  Future<void> commit() => widget.store.saveImport(
    widget.draft,
    name: _name.text,
    username: _user.text,
    password: _password.text,
  );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final draft = widget.draft;
    final profile = draft.profile;
    final missing =
        profile.kind == VpnKind.openvpn || profile.kind == VpnKind.pptp
        ? _missingPlugin(widget.store, profile.kind)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?missing,
        SettingsSection(
          label: 'Connection',
          children: [
            _field('Name', _name, autofocus: true),
            SettingsRow(
              label: 'Type',
              control: _readOnly(theme, profile.kindLabel),
            ),
            if (profile.server.isNotEmpty)
              SettingsRow(
                label: 'Server',
                control: _readOnly(theme, profile.server),
              ),
            if (profile.interfaceName.isNotEmpty)
              SettingsRow(
                label: 'Interface',
                info:
                    'The network interface the tunnel appears as. Taken from '
                    'the file\'s name where that is free.',
                control: _readOnly(theme, profile.interfaceName),
              ),
          ],
        ),
        if (draft.asksPassword) ...[
          const SizedBox(height: 20),
          SettingsSection(
            label: 'Sign in',
            info:
                'The file says this VPN signs in with a password but cannot '
                'carry one. Leave it empty to be asked when it fails to '
                'connect.',
            children: [
              _field('User name', _user),
              _field(
                'Password',
                _password,
                obscure: true,
                onSubmitted: (_) {
                  save();
                },
              ),
            ],
          ),
        ],
        if (draft.warnings.isNotEmpty) ...[
          const SizedBox(height: 20),
          SettingsSection(
            label: 'Left out',
            children: [for (final w in draft.warnings) SettingsHint(w)],
          ),
        ],
        actions(),
      ],
    );
  }
}

// --- Password ----------------------------------------------------------------

class _PasswordForm extends StatefulWidget {
  const _PasswordForm({
    required this.store,
    required this.profile,
    required this.onSaved,
    required this.onCancel,
  });

  final VpnStore store;
  final VpnProfile profile;
  final VoidCallback onSaved;
  final VoidCallback onCancel;

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm>
    with _VpnFormState<_PasswordForm> {
  late final _user = controller();
  late final _password = controller();

  @override
  void initState() {
    super.initState();
    unawaited(
      widget.store.usernameOf(widget.profile).then((name) {
        if (mounted && _user.text.isEmpty) _user.text = name;
      }),
    );
  }

  @override
  VoidCallback get onSaved => widget.onSaved;
  @override
  VoidCallback get onCancel => widget.onCancel;

  @override
  String? validate() => _password.text.isEmpty ? 'Enter the password.' : null;

  @override
  Future<void> commit() async {
    await widget.store.setPassword(
      widget.profile,
      password: _password.text,
      username: _user.text,
    );
    // The password was asked for to connect: do it, rather than leave the
    // user to find the switch again.
    unawaited(widget.store.setEnabled(widget.profile, true));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          label: 'Sign in',
          info:
              'Saved in the profile by NetworkManager, so it is not asked '
              'for again.',
          children: [
            _field('User name', _user),
            _field(
              'Password',
              _password,
              obscure: true,
              autofocus: true,
              onSubmitted: (_) {
                save();
              },
            ),
          ],
        ),
        actions(saveLabel: 'Save and connect'),
      ],
    );
  }
}
