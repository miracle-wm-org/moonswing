---
title: Adding a module or widget
description: What a Module is, how config reaches it live, and how desktop widgets differ.
sidebar:
  order: 7
---

## Modules

A `Module` is a panel strip sized by its content. It is three things: a `configKey` matching a
`[modules.<key>]` table, a `loadConfig(map)`, and a `builder`.

Adding one is a top-level declaration plus a registration:

```dart
final myModule = Module.simple(
  configKey: 'my_module',
  fromMap: MyModuleConfig.fromMap,
  builder: (context, config) => MyModuleWidget(config: config),
);

// in main.dart, above runWidget:
Module.register(myModule);
```

`Module.plain` is the variant for a module with no config of its own.
`test/module_registry_test.dart` pins the registry, so a new module is a change to that test
too.

### Config reaches a module imperatively

Config is pushed, not passed: `Module.loadAll` mutates each module's config in place, so
nothing about a module widget's *inputs* tells Flutter that anything moved.
`Module.configChanges` is what keeps `[modules.*]` options live.

`loadConfig` compares a stringified signature of the raw sub-map, and `loadAll` fires the
notifier once per sweep. A panel listens per module, so a `[modules.clock]` edit rebuilds the
clock and nothing else. That guard also stops a side-effecting `fromMap` from re-running on
every keystroke.

Remember that a `fromMap` runs inside `AppConfig.fromMap`, so a throw out of it discards the
user's entire config. Read every field through `TomlReader`.

## Desktop widgets

`DesktopWidgetRegistry` is the same shape for the desktop grid, and it is deliberately
separate. A desktop widget is a rectangle of cells the user resizes, so its spec carries span
limits — and those are clamped at **render** time, never written back, so a layout authored
under different limits survives. An unknown type renders as a placeholder and is left exactly
as authored.

## The compositor's own configuration

Settings › Window Manager edits `~/.config/miracle-wm/config.yaml` through `MiracleConfig`,
`package:miracle`'s FFI wrapper around `libmiracle-wm-c`. It is the one pane that writes
*another program's* file, and three things follow — none of which is how the Shell pane works.

- **Nothing is written until Save.** `ConfigStore` debounces every keystroke to disk because the
  shell re-reads its own config live. A compositor does not, so a half-typed border size written
  as it is typed is what the user's next `reload_config` would apply — and a compositor that
  will not start has no settings page to fix it from. So `MiracleConfigStore` accumulates edits
  in native memory, `save()` is a deliberate act, and `reset()` re-reads the file.
  **A save is only half the job**: miracle does not watch its own configuration, so the pane
  names the shortcut that reloads it, read off `builtInKeyCommandOverrides` rather than
  hard-coded, because it can be rebound.
- **The lease frees native memory, except while dirty.** One loaded tree for the machine,
  `acquire()`/`release()` as everywhere else — but a release that would discard unsaved edits
  keeps the tree instead. The bound is the user's own Save or Reset.
- **Rows subscribe per value; lists subscribe on a signature.** `MiracleValue` is a
  `StoreSelector` over one FFI getter, which is what stops one digit rebuilding twenty rows. A
  collection cannot be one — the live `List` views mint a fresh Dart object per read — so
  `MiracleCollection` compares a *spelling* of what the editor renders. And because a
  `SettingsTextField` seeds its controller once, anything that replaces or reorders a list goes
  through `editStructure`, whose revision keys the rows.

Two hazards the package documents and the pane has to respect: an unset keymap must never have
its options touched (the C library dereferences it unchecked and aborts), and the key-repeat
settings are dropped by a save unless a keymap is set.

`miracle_config/` is otherwise Flutter-free — the keysym table, the enum labels and the colour
conversion are plain Dart, because that is what `test/miracle_config_test.dart` can reach on a
machine with no compositor.
