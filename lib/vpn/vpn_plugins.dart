// Which NetworkManager VPN plugins are installed.
//
// A plugin registers itself with a keyfile, `<name>.name`, in one of two
// directories — the same files `nm_vpn_plugin_info_list_load()` and the daemon
// read — naming its D-Bus service and the libnm half that imports files. The
// pane reads them for two answers: whether the OpenVPN or PPTP form can make a
// profile that will ever connect (without the plugin, NetworkManager refuses to
// start one), and which plugins to offer a file to on import.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show immutable;

import 'package:moonswing/vpn/vpn_model.dart';

/// Where NetworkManager looks, in its own order: the administrator's
/// directory first, so a file there shadows the packaged one of that name.
const List<String> kVpnPluginDirs = [
  '/etc/NetworkManager/VPN',
  '/usr/lib/NetworkManager/VPN',
];

@immutable
class VpnPluginInfo {
  const VpnPluginInfo({
    required this.file,
    required this.name,
    required this.service,
    this.aliases = const [],
    this.libnmPlugin = '',
  });

  /// The `.name` file it was read from — what libnm loads it by.
  final String file;

  /// `[VPN Connection] name`, e.g. `openvpn`.
  final String name;

  /// `[VPN Connection] service`, e.g. `org.freedesktop.NetworkManager.openvpn`.
  final String service;
  final List<String> aliases;

  /// `[libnm] plugin`: the library that imports and exports files. Empty for
  /// a plugin with none, which cannot import.
  final String libnmPlugin;

  VpnKind get kind => vpnKindOfService(service);

  bool serves(String serviceType) =>
      service == serviceType || aliases.contains(serviceType);
}

/// Reads one `.name` keyfile, or null for one without a name and service.
VpnPluginInfo? parseVpnPluginFile(String path, String text) {
  String? section;
  final values = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1).trim();
      continue;
    }
    final eq = line.indexOf('=');
    if (eq < 0 || section == null) continue;
    values['$section/${line.substring(0, eq).trim()}'] = line
        .substring(eq + 1)
        .trim();
  }
  final name = values['VPN Connection/name'] ?? '';
  final service = values['VPN Connection/service'] ?? '';
  if (name.isEmpty || service.isEmpty) return null;
  return VpnPluginInfo(
    file: path,
    name: name,
    service: service,
    aliases: [
      for (final a in (values['VPN Connection/aliases'] ?? '').split(';'))
        if (a.trim().isNotEmpty) a.trim(),
    ],
    libnmPlugin: values['libnm/plugin'] ?? '',
  );
}

/// Every installed plugin, one per service, the earlier directory winning.
/// A directory that is missing or unreadable is simply empty.
List<VpnPluginInfo> readVpnPlugins({List<String> dirs = kVpnPluginDirs}) {
  final byService = <String, VpnPluginInfo>{};
  for (final dir in dirs) {
    final List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync()
        ..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException {
      continue;
    }
    for (final entry in entries) {
      if (entry is! File || !entry.path.endsWith('.name')) continue;
      try {
        final info = parseVpnPluginFile(entry.path, entry.readAsStringSync());
        if (info != null) byService.putIfAbsent(info.service, () => info);
      } on FileSystemException {
        // One unreadable file costs that plugin.
      }
    }
  }
  return byService.values.toList(growable: false);
}

/// The plugin a form's kind needs, by its upstream project name — what every
/// distribution's package is called, give or take the case.
String vpnPluginPackage(VpnKind kind) => switch (kind) {
  VpnKind.openvpn => 'NetworkManager-openvpn',
  VpnKind.pptp => 'NetworkManager-pptp',
  _ => '',
};
