// What `moonswing-mcp` offers a model: the tool table.
//
// Three families, each of which works without the others:
//
//  * `wm_*` — the window manager over its IPC socket (`compositor_client.dart`):
//    what is open where, and moving, resizing, focusing and arranging it. Every
//    one of these is a command `miraclemsg` would accept, and `wm_run_command`
//    is `miraclemsg` itself for whatever the helpers do not cover.
//  * `shell_*`, `todo_*`, `note_*` — the shell over `org.moonswing.Shell`
//    (`lib/control/`), which needs Moonswing running.
//  * `media_*` and `shell_send_notification` — MPRIS and the freedesktop
//    notification interface, which any desktop answers.
//
// Descriptions are written for a model that has never seen this desktop: what
// the tool does, what its ids are and where they come from, and what to call
// first. Names are snake case under 64 characters, which every client accepts.
library;

import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:miracle/miracle.dart';

import 'package:moonswing/control/control_api.dart';
import 'package:moonswing/mcp/compositor_client.dart';
import 'package:moonswing/mcp/mcp_protocol.dart';
import 'package:moonswing/mcp/shell_client.dart';

/// What the server tells the client to put in front of the model.
const String kMoonswingMcpInstructions = '''
These tools drive the user's Linux desktop: the Moonswing shell (panels, launcher, overview, notifications, todo board, timers, themes) and its window manager, miracle-wm (or any i3-compatible one, such as sway).

Windows: call wm_list_windows first. Every window has a numeric "id"; the other wm_* tools take it as window_id. Leaving window_id out acts on the focused window. Workspaces are named or numbered; outputs are connector names like "DP-1".
To arrange windows side by side: put them on one workspace (wm_move_window), choose the split with wm_set_layout ("splith" for side by side, "splitv" for stacked, "tabbed"), and size them with wm_resize_window (unit "ppt" is percent of the parent).
wm_run_command sends any miracle/i3 command verbatim, e.g. "[con_id=12] move left" or "workspace 3; layout tabbed".

The shell: shell_status says what is running. To open an application, find its id with shell_search_apps and call shell_launch_app. shell_screenshot returns a picture of a screen, for when you need to see what the user sees.

Act on what the user asked for. Closing windows, deleting cards and dismissing notifications cannot be undone; confirm with the user before doing them unprompted.''';

/// The prefixes `--only` accepts.
const List<String> kMoonswingToolGroups = ['wm', 'shell', 'todo', 'note', 'media'];

/// Which tools to offer.
class MoonswingToolOptions {
  const MoonswingToolOptions({
    this.readOnly = false,
    this.allowExec = false,
    this.groups,
  });

  /// Only the tools whose name starts with one of these and an underscore
  /// (`--only wm,todo`), or every tool when null. A small model choosing among
  /// forty tools picks worse than one choosing among ten.
  final Set<String>? groups;

  /// Only tools that change nothing (`--read-only`).
  final bool readOnly;

  /// Whether `exec` may be sent to the window manager (`--allow-exec`) —
  /// `wm_exec`, and an `exec` inside `wm_run_command`. Off by default: it runs
  /// any command line as the user, and launching an application is what
  /// `shell_launch_app` is for.
  final bool allowExec;
}

List<McpTool> buildMoonswingTools({
  required CompositorClient wm,
  required ShellBusClient shell,
  MoonswingToolOptions options = const MoonswingToolOptions(),
}) {
  final tools = [
    ..._windowManagerTools(wm, options),
    ..._shellTools(shell),
    ..._mediaTools(shell),
  ];
  final groups = options.groups;
  return [
    for (final tool in tools)
      if (!options.readOnly || tool.readOnly)
        if (groups == null || groups.contains(tool.name.split('_').first)) tool,
  ];
}

// --- the window manager ------------------------------------------------------

final Map<String, Object?> _windowId = Schema.integer(
    'The window\'s id from wm_list_windows. Omit to act on the focused window.');

String _scope(McpArgs args) {
  final id = args.optionalInteger('window_id', min: 0);
  return id == null ? '' : '${windowCriteria(id)} ';
}

/// Whether [command] would run `exec` — any of its `;`/`,`-separated parts,
/// criteria stripped. Best effort, and only ever errs towards refusing.
bool commandRunsExec(String command) {
  for (final part in command.split(RegExp('[;,\n]'))) {
    final bare = part.trim().replaceFirst(RegExp(r'^\[[^\]]*\]\s*'), '');
    if (RegExp(r'^exec(_always)?\b').hasMatch(bare)) return true;
  }
  return false;
}

Future<McpToolResult> _run(CompositorClient wm, List<String> commands) async {
  final outcomes = <Map<String, Object?>>[];
  var failed = false;
  for (final command in commands) {
    final results = await wm.command(command);
    for (final result in results) {
      if (!result.success) failed = true;
    }
    outcomes.add({
      'command': command,
      'results': [
        for (final result in results)
          {
            'success': result.success,
            if (result.error != null) 'error': result.error,
            if (result.parseError) 'parse_error': true,
          },
      ],
    });
  }
  final text = const JsonEncoder.withIndent('  ').convert(
      outcomes.length == 1 ? outcomes.single : outcomes);
  return McpToolResult.text(text, isError: failed);
}

String _workspaceTarget(String workspace) {
  final number = int.tryParse(workspace.trim());
  return number != null
      ? 'number $number'
      : commandArgument(workspace.trim());
}

List<McpTool> _windowManagerTools(
    CompositorClient wm, MoonswingToolOptions options) {
  return [
    McpTool(
      name: 'wm_status',
      title: 'Window manager status',
      description: 'Which window manager is running (miracle-wm or another '
          'i3-compatible one), its version, its screens and the focused '
          'workspace.',
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final version = await wm.version();
        final workspaces = await wm.workspaces();
        final outputs = await wm.outputs();
        return McpToolResult.json({
          'window_manager': wm.flavour?.label,
          'version': version.humanReadable,
          'socket': wm.path,
          'focused_workspace': workspaces
              .where((w) => w.focused)
              .map((w) => w.name)
              .firstOrNull,
          'outputs': [
            for (final output in outputs)
              if (output.active) output.name,
          ],
        });
      },
    ),
    McpTool(
      name: 'wm_list_windows',
      title: 'List windows',
      description: 'Every open window: its id (what every other wm_* tool '
          'takes as window_id), app_id, title, workspace, output, whether it '
          'is focused, floating or fullscreen, and its rectangle in global '
          'logical pixels. Windows on the scratchpad are not listed.',
      properties: {
        'workspace': Schema.string('Only windows on this workspace.'),
        'app_id': Schema.string(
            'Only windows whose app_id contains this, case-insensitively.'),
      },
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final workspace = args.optionalString('workspace');
        final appId = args.optionalString('app_id')?.toLowerCase();
        final windows = describeWindows(await wm.tree()).where((w) {
          if (workspace != null &&
              w['workspace'] != workspace &&
              '${w['workspace_number']}' != workspace) {
            return false;
          }
          if (appId != null &&
              !('${w['app_id'] ?? ''}'.toLowerCase().contains(appId))) {
            return false;
          }
          return true;
        }).toList();
        return McpToolResult.json(windows);
      },
    ),
    McpTool(
      name: 'wm_list_workspaces',
      title: 'List workspaces',
      description: 'Every workspace: name, number, which screen it is on, '
          'whether it is focused or visible, its layout, and the ids of the '
          'windows on it.',
      readOnly: true,
      idempotent: true,
      handler: (args) async =>
          McpToolResult.json(describeWorkspaces(await wm.tree())),
    ),
    McpTool(
      name: 'wm_list_outputs',
      title: 'List screens',
      description: 'Every screen (output): connector name, make and model, '
          'whether it is active or primary, scale, position and size, its '
          'current mode and the workspace it shows.',
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final outputs = await wm.outputs();
        return McpToolResult.json([
          for (final output in outputs)
            {
              'name': output.name,
              'make': output.make,
              'model': output.model,
              'active': output.active,
              'primary': output.primary,
              'scale': output.scale,
              if (output.rect != null) 'rect': describeRect(output.rect!),
              if (output.currentMode != null)
                'mode': '${output.currentMode!.width}x'
                    '${output.currentMode!.height}@'
                    '${output.currentMode!.refreshHz.toStringAsFixed(2)}Hz',
              'current_workspace': output.currentWorkspace,
            },
        ]);
      },
    ),
    McpTool(
      name: 'wm_run_command',
      title: 'Run window manager commands',
      description: 'Sends commands to the window manager verbatim, as '
          '`miraclemsg <command>` would: i3 command syntax with optional '
          'criteria and ";" between commands. Examples: "[con_id=12] focus", '
          '"[app_id=\\"firefox\\"] move to workspace 2", "workspace 3; layout '
          'tabbed", "resize set width 50 ppt", "gaps inner all set 8", '
          '"floating toggle", "move scratchpad", "scratchpad show". '
          'miracle-wm supports exec, split, layout, focus, move, mark, '
          'unmark, resize, swap, sticky, workspace, rename workspace, gaps, '
          'scratchpad, floating and fullscreen. Each command\'s result is '
          'returned; an unsupported one reports a parse error.',
      properties: {
        'command': Schema.string('One command line.'),
        'commands':
            Schema.strings('Several command lines, run in order, instead.'),
        'window_id': Schema.integer(
            'Prefix every command with [con_id=<window_id>].'),
      },
      handler: (args) async {
        final commands = [
          ?args.optionalString('command'),
          ...?args.optionalStrings('commands'),
        ].where((c) => c.trim().isNotEmpty).toList();
        if (commands.isEmpty) {
          throw const McpToolException('Give "command" or "commands".');
        }
        if (!options.allowExec && commands.any(commandRunsExec)) {
          throw const McpToolException(
              'exec is switched off for this MCP server (start it with '
              '--allow-exec to allow it). To open an application use '
              'shell_search_apps and shell_launch_app.');
        }
        final scope = _scope(args);
        return _run(wm, [for (final c in commands) '$scope$c']);
      },
    ),
    McpTool(
      name: 'wm_focus_window',
      title: 'Focus a window',
      description: 'Focuses a window, switching to its workspace. Give its '
          'window_id from wm_list_windows, or an app_id to focus the first '
          'window of that application.',
      properties: {
        'window_id': Schema.integer('The window\'s id.'),
        'app_id': Schema.string('The application\'s app_id, exactly.'),
      },
      idempotent: true,
      handler: (args) async {
        final id = args.optionalInteger('window_id', min: 0);
        final appId = args.optionalString('app_id');
        if (id == null && appId == null) {
          throw const McpToolException('Give "window_id" or "app_id".');
        }
        final criteria = id != null
            ? windowCriteria(id)
            : Criteria(appId: appId).toString();
        return _run(wm, ['$criteria focus']);
      },
    ),
    McpTool(
      name: 'wm_move_window',
      title: 'Move a window',
      description: 'Moves a window to a workspace, to a screen, one step in a '
          'direction within its layout, to the centre (floating windows), or '
          'to the scratchpad. Give exactly one destination. With follow, focus '
          'goes with it.',
      properties: {
        'window_id': _windowId,
        'workspace': Schema.string(
            'A workspace name or number; created if it does not exist.'),
        'output': Schema.string(
            'A screen\'s connector name (wm_list_outputs), or left/right/up/down.'),
        'direction': Schema.string('Swap one step this way in the layout.',
            oneOf: ['left', 'right', 'up', 'down']),
        'center': Schema.boolean('Centre a floating window on its screen.'),
        'scratchpad': Schema.boolean('Hide the window on the scratchpad.'),
        'follow': Schema.boolean(
            'Switch to the destination afterwards (workspace or output only).'),
      },
      handler: (args) async {
        final scope = _scope(args);
        final workspace = args.optionalString('workspace');
        final output = args.optionalString('output');
        final direction = args.optionalString('direction');
        final center = args.optionalBool('center') ?? false;
        final scratchpad = args.optionalBool('scratchpad') ?? false;
        final chosen = [
          workspace != null,
          output != null,
          direction != null,
          center,
          scratchpad,
        ].where((b) => b).length;
        if (chosen != 1) {
          throw const McpToolException('Give exactly one of "workspace", '
              '"output", "direction", "center" or "scratchpad".');
        }
        final follow = args.optionalBool('follow') ?? false;
        final commands = <String>[];
        if (workspace != null) {
          final target = _workspaceTarget(workspace);
          commands.add('${scope}move container to workspace $target');
          if (follow) commands.add('workspace $target');
        } else if (output != null) {
          final target = commandArgument(output.trim());
          commands.add('${scope}move container to output $target');
          if (follow) commands.add('focus output $target');
        } else if (direction != null) {
          args.choice('direction', const ['left', 'right', 'up', 'down']);
          commands.add('${scope}move $direction');
        } else if (center) {
          commands.add('${scope}move position center');
        } else {
          commands.add('${scope}move scratchpad');
        }
        return _run(wm, commands);
      },
    ),
    McpTool(
      name: 'wm_switch_workspace',
      title: 'Switch workspace',
      description: 'Shows a workspace on its screen: by name or number '
          '(created if it does not exist), or the next, previous, or the one '
          'shown before this one.',
      properties: {
        'workspace': Schema.string('A workspace name or number.'),
        'relative': Schema.string('Instead of a name.',
            oneOf: ['next', 'prev', 'next_on_output', 'prev_on_output',
                'back_and_forth']),
      },
      idempotent: true,
      handler: (args) async {
        final workspace = args.optionalString('workspace');
        final relative = args.optionalString('relative');
        if ((workspace == null) == (relative == null)) {
          throw const McpToolException('Give "workspace" or "relative".');
        }
        if (workspace != null) {
          return _run(wm, ['workspace ${_workspaceTarget(workspace)}']);
        }
        args.choice('relative', const [
          'next',
          'prev',
          'next_on_output',
          'prev_on_output',
          'back_and_forth',
        ]);
        return _run(wm, ['workspace $relative']);
      },
    ),
    McpTool(
      name: 'wm_set_layout',
      title: 'Set a layout',
      description: 'Sets how the container holding a window arranges its '
          'children: "splith" side by side, "splitv" one above another, '
          '"tabbed", "stacking", or "toggle_split" to flip between the two '
          'splits. "split_horizontal"/"split_vertical" instead make the window '
          'itself a new split, so the next window opened beside it lands that '
          'way.',
      properties: {
        'window_id': _windowId,
        'layout': Schema.string('The layout.', oneOf: [
          'splith',
          'splitv',
          'tabbed',
          'stacking',
          'default',
          'toggle_split',
          'split_horizontal',
          'split_vertical',
        ]),
      },
      required: ['layout'],
      idempotent: true,
      handler: (args) async {
        final layout = args.choice('layout', const [
          'splith',
          'splitv',
          'tabbed',
          'stacking',
          'default',
          'toggle_split',
          'split_horizontal',
          'split_vertical',
        ]);
        final command = switch (layout) {
          'toggle_split' => 'layout toggle split',
          'split_horizontal' => 'split horizontal',
          'split_vertical' => 'split vertical',
          _ => 'layout $layout',
        };
        return _run(wm, ['${_scope(args)}$command']);
      },
    ),
    McpTool(
      name: 'wm_resize_window',
      title: 'Resize a window',
      description: 'Sets a window\'s width and/or height. Unit "ppt" is '
          'percent of the space its container has (50 is half), "px" is '
          'logical pixels. For a tiled window this moves the split beside it.',
      properties: {
        'window_id': _windowId,
        'width': Schema.integer('The new width.', min: 1),
        'height': Schema.integer('The new height.', min: 1),
        'unit': Schema.string('Defaults to ppt.', oneOf: ['ppt', 'px']),
      },
      idempotent: true,
      handler: (args) async {
        final width = args.optionalInteger('width', min: 1);
        final height = args.optionalInteger('height', min: 1);
        if (width == null && height == null) {
          throw const McpToolException('Give "width", "height" or both.');
        }
        final unit = args.choice('unit', const ['ppt', 'px'], fallback: 'ppt');
        return _run(wm, [
          '${_scope(args)}resize set'
              '${width == null ? '' : ' width $width $unit'}'
              '${height == null ? '' : ' height $height $unit'}',
        ]);
      },
    ),
    McpTool(
      name: 'wm_set_window_state',
      title: 'Float, fullscreen or pin a window',
      description: 'Turns a window\'s floating, fullscreen or sticky state on, '
          'off, or toggles it. Sticky floating windows stay on screen across '
          'workspaces.',
      properties: {
        'window_id': _windowId,
        'floating': Schema.string('', oneOf: ['enable', 'disable', 'toggle']),
        'fullscreen': Schema.string('', oneOf: ['enable', 'disable', 'toggle']),
        'sticky': Schema.string('', oneOf: ['enable', 'disable', 'toggle']),
      },
      handler: (args) async {
        const states = ['enable', 'disable', 'toggle'];
        final scope = _scope(args);
        final commands = [
          for (final key in const ['floating', 'fullscreen', 'sticky'])
            if (args.has(key)) '$scope$key ${args.choice(key, states)}',
        ];
        if (commands.isEmpty) {
          throw const McpToolException(
              'Give "floating", "fullscreen" or "sticky".');
        }
        return _run(wm, commands);
      },
    ),
    McpTool(
      name: 'wm_close_window',
      title: 'Close a window',
      description: 'Asks a window to close, as its close button would. The '
          'application may ask to save first. Cannot be undone.',
      properties: {'window_id': Schema.integer('The window\'s id.')},
      required: ['window_id'],
      destructive: true,
      handler: (args) async => _run(wm, [
        '${windowCriteria(args.integer('window_id', min: 0))} kill',
      ]),
    ),
    if (options.allowExec)
      McpTool(
        name: 'wm_exec',
        title: 'Run a command line',
        description: 'Starts a command line through the window manager '
            '(`exec`), detached, as the user. Prefer shell_launch_app for '
            'installed applications.',
        properties: {'command': Schema.string('The command line.')},
        required: ['command'],
        handler: (args) async =>
            _run(wm, ['exec ${args.string('command')}']),
      ),
  ];
}

// --- the shell ---------------------------------------------------------------

String _str(DBusValue value) => (value as DBusString).value;

Object? _plain(DBusValue value) => switch (value) {
      DBusString(:final value) => value,
      DBusBoolean(:final value) => value,
      DBusInt64(:final value) => value,
      DBusUint32(:final value) => value,
      DBusInt32(:final value) => value,
      DBusDouble(:final value) => value,
      DBusVariant(:final value) => _plain(value),
      DBusArray(:final children) => [for (final c in children) _plain(c)],
      _ => value.toNative(),
    };

String _formatDuration(int milliseconds) {
  final total = milliseconds ~/ 1000;
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

List<McpTool> _shellTools(ShellBusClient shell) {
  Future<McpToolResult> done(String method, List<DBusValue> args,
      String message) async {
    await shell.callShell(method, args, '');
    return McpToolResult.text(message);
  }

  final actionIds = [for (final a in ShellAction.values) a.id];
  return [
    McpTool(
      name: 'shell_status',
      title: 'Shell status',
      description: 'Whether Moonswing is running and what it is doing: the '
          'theme, do-not-disturb, notification counts, whether it is '
          'recording or locked, how many timers run, whether the todo board '
          'loaded and whether screenshots are allowed.',
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final values = await shell.callShell('GetStatus', const [], 'a{sv}');
        final dict = values.first as DBusDict;
        return McpToolResult.json({
          for (final entry in dict.children.entries)
            _str(entry.key): _plain(entry.value),
        });
      },
    ),
    McpTool(
      name: 'shell_run_action',
      title: 'Run a shell action',
      description: 'Does what one of the shell\'s global shortcuts does. '
          'Most are toggles: running one twice opens and then closes it. '
          '${[for (final a in ShellAction.values) '"${a.id}": ${a.description}'].join('; ')}.',
      properties: {
        'action': Schema.string('The action.', oneOf: actionIds),
      },
      required: ['action'],
      handler: (args) async {
        final action = args.choice('action', actionIds);
        return done('Activate', [DBusString(action)], 'Ran $action.');
      },
    ),
    McpTool(
      name: 'shell_open_overview',
      title: 'Open the overview',
      description: 'Opens the overview — the shell\'s full-screen panel — on '
          'a tab: calendar, system (resource monitor), systeminfo, settings, '
          'todo (the kanban board), code (review requests and pull requests), '
          'shortcuts (the key-binding cheat sheet). Never closes it.',
      properties: {
        'tab': Schema.string('The tab.', oneOf: kControlOverviewTabs),
      },
      required: ['tab'],
      idempotent: true,
      handler: (args) async {
        final tab = args.choice('tab', kControlOverviewTabs);
        return done('OpenOverview', [DBusString(tab)], 'Opened the $tab tab.');
      },
    ),
    McpTool(
      name: 'shell_open_settings',
      title: 'Open a settings page',
      description: 'Opens Settings on a page for the user to look at or '
          'change: a category, or one bar module\'s own page by its config key '
          '(clock, weather, battery, workspaces, dock, launcher, …).',
      properties: {
        'category': Schema.string('A settings category.',
            oneOf: kControlSettingsCategories),
        'module': Schema.string('A module\'s config key, instead.'),
      },
      idempotent: true,
      handler: (args) async {
        final module = args.optionalString('module') ?? '';
        final category = module.isEmpty
            ? args.choice('category', kControlSettingsCategories,
                fallback: 'shell')
            : '';
        return done('OpenSettings', [DBusString(category), DBusString(module)],
            'Opened settings${module.isEmpty ? ' › $category' : ' for $module'}.');
      },
    ),
    McpTool(
      name: 'shell_list_themes',
      title: 'List themes',
      description: 'The installed themes, by slug (what shell_set_theme '
          'takes) and display name; shell_status names the active one.',
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final values = await shell.callShell('ListThemes', const [], 'a(ssb)');
        return McpToolResult.json([
          for (final row in (values.first as DBusArray).children)
            {
              'slug': _str((row as DBusStruct).children[0]),
              'name': _str(row.children[1]),
              'built_in': (row.children[2] as DBusBoolean).value,
            },
        ]);
      },
    ),
    McpTool(
      name: 'shell_set_theme',
      title: 'Switch theme',
      description: 'Switches the whole shell to a theme, by slug.',
      properties: {'slug': Schema.string('From shell_list_themes.')},
      required: ['slug'],
      idempotent: true,
      handler: (args) async {
        final slug = args.string('slug');
        return done('SetTheme', [DBusString(slug)], 'Switched to $slug.');
      },
    ),
    McpTool(
      name: 'shell_search_apps',
      title: 'Find applications',
      description: 'Searches the installed applications the way the launcher '
          'does, best match first. Each result\'s id is what '
          'shell_launch_app takes. An empty query lists them all.',
      properties: {
        'query': Schema.string('Name, description or keyword.'),
        'limit': Schema.integer('At most this many; default 10.',
            min: 1, max: 200),
      },
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final values = await shell.callShell(
          'SearchApps',
          [
            DBusString(args.optionalString('query') ?? ''),
            DBusUint32(args.optionalInteger('limit', min: 1, max: 200) ?? 10),
          ],
          'a(sss)',
        );
        return McpToolResult.json([
          for (final row in (values.first as DBusArray).children)
            {
              'id': _str((row as DBusStruct).children[0]),
              'name': _str(row.children[1]),
              if (_str(row.children[2]).isNotEmpty)
                'description': _str(row.children[2]),
            },
        ]);
      },
    ),
    McpTool(
      name: 'shell_launch_app',
      title: 'Launch an application',
      description: 'Starts an installed application by its id from '
          'shell_search_apps (its desktop entry, e.g. "firefox" or '
          '"org.gnome.Nautilus"). Its window appears on the focused '
          'workspace; wm_list_windows finds it once it has mapped.',
      properties: {'app_id': Schema.string('The application id.')},
      required: ['app_id'],
      handler: (args) async {
        final id = args.string('app_id');
        return done('LaunchApp', [DBusString(id)], 'Launched $id.');
      },
    ),
    McpTool(
      name: 'shell_screenshot',
      title: 'Look at a screen',
      description: 'Takes a picture of one screen and returns it, so you can '
          'see what the user sees. Defaults to the focused screen, scaled to '
          'at most 1600 pixels wide. Not saved to the user\'s screenshot '
          'folder, and makes no sound.',
      properties: {
        'output': Schema.string(
            'A screen\'s connector name from wm_list_outputs; default focused.'),
        'max_width': Schema.integer(
            'Scale down to at most this width; 0 for full size.',
            min: 0, max: 8192),
      },
      readOnly: true,
      handler: (args) async {
        final values = await shell.callShell(
          'Screenshot',
          [
            DBusString(args.optionalString('output') ?? ''),
            DBusUint32(args.optionalInteger('max_width', min: 0, max: 8192) ??
                1600),
          ],
          'ay',
        );
        final png = (values.first as DBusArray)
            .children
            .map((b) => (b as DBusByte).value)
            .toList();
        return McpToolResult([
          McpImage(base64Encode(png)),
          McpText('Screenshot of ${args.optionalString('output') ?? 'the '
              'focused screen'}.'),
        ]);
      },
    ),
    // Notifications.
    McpTool(
      name: 'shell_list_notifications',
      title: 'List notifications',
      description: 'The notifications in the shell\'s notification panel, '
          'newest first: id, app, summary, body, when it arrived and whether '
          'it has been read.',
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final values =
            await shell.callShell('ListNotifications', const [], 'a(usssxb)');
        return McpToolResult.json([
          for (final row in (values.first as DBusArray).children)
            {
              'id': ((row as DBusStruct).children[0] as DBusUint32).value,
              'app': _str(row.children[1]),
              'summary': _str(row.children[2]),
              'body': _str(row.children[3]),
              'arrived': DateTime.fromMillisecondsSinceEpoch(
                      (row.children[4] as DBusInt64).value)
                  .toIso8601String(),
              'read': (row.children[5] as DBusBoolean).value,
            },
        ]);
      },
    ),
    McpTool(
      name: 'shell_send_notification',
      title: 'Send a notification',
      description: 'Shows the user a desktop notification — for telling them '
          'something finished, or reminding them later in a conversation.',
      properties: {
        'summary': Schema.string('The headline.'),
        'body': Schema.string('More detail; optional.'),
        'urgency': Schema.string('Default normal.',
            oneOf: ['low', 'normal', 'critical']),
      },
      required: ['summary'],
      handler: (args) async {
        final id = await shell.notify(
          summary: args.string('summary'),
          body: args.optionalString('body') ?? '',
          urgency: args.choice('urgency', const ['low', 'normal', 'critical'],
              fallback: 'normal'),
        );
        return McpToolResult.text('Posted notification $id.');
      },
    ),
    McpTool(
      name: 'shell_dismiss_notification',
      title: 'Dismiss notifications',
      description: 'Removes one notification from the panel by id, or all of '
          'them. Cannot be undone.',
      properties: {
        'id': Schema.integer('From shell_list_notifications.', min: 1),
        'all': Schema.boolean('Dismiss every notification instead.'),
      },
      destructive: true,
      handler: (args) async {
        final all = args.optionalBool('all') ?? false;
        final id = args.optionalInteger('id', min: 1);
        if (all == (id != null)) {
          throw const McpToolException('Give "id" or "all": true.');
        }
        return done('DismissNotification', [DBusUint32(id ?? 0)],
            all ? 'Dismissed every notification.' : 'Dismissed $id.');
      },
    ),
    McpTool(
      name: 'shell_set_do_not_disturb',
      title: 'Do not disturb',
      description: 'Silences notification pop-ups and sounds, or lets them '
          'through again. Notifications still collect in the panel.',
      properties: {'enabled': Schema.boolean('True to silence.')},
      required: ['enabled'],
      idempotent: true,
      handler: (args) async {
        final enabled = args.optionalBool('enabled')!;
        return done('SetDoNotDisturb', [DBusBoolean(enabled)],
            'Do not disturb is ${enabled ? 'on' : 'off'}.');
      },
    ),
    // Timers.
    McpTool(
      name: 'shell_list_timers',
      title: 'List timers',
      description: 'The running and paused countdowns and stopwatches: id, '
          'label, and time left (countdown) or spent (stopwatch).',
      readOnly: true,
      handler: (args) async {
        final values = await shell.callShell('ListTimers', const [], 'a(ubsbbt)');
        return McpToolResult.json([
          for (final row in (values.first as DBusArray).children)
            {
              'id': ((row as DBusStruct).children[0] as DBusUint32).value,
              'kind': (row.children[1] as DBusBoolean).value
                  ? 'stopwatch'
                  : 'timer',
              if (_str(row.children[2]).isNotEmpty) 'label': _str(row.children[2]),
              'running': (row.children[3] as DBusBoolean).value,
              'finished': (row.children[4] as DBusBoolean).value,
              'reading': _formatDuration((row.children[5] as DBusUint64).value),
            },
        ]);
      },
    ),
    McpTool(
      name: 'shell_start_timer',
      title: 'Start a timer',
      description: 'Starts a countdown that rings and posts a notification '
          'when it reaches zero ("remind me in 10 minutes"), or a stopwatch. '
          'Give the duration as hours, minutes and/or seconds.',
      properties: {
        'hours': Schema.integer('', min: 0, max: 99),
        'minutes': Schema.integer('', min: 0),
        'seconds': Schema.integer('', min: 0),
        'label': Schema.string('What it is for, shown on the timer.'),
        'stopwatch': Schema.boolean('Start a stopwatch instead.'),
      },
      handler: (args) async {
        if (args.optionalBool('stopwatch') ?? false) {
          final values =
              await shell.callShell('StartStopwatch', const [], 'u');
          return McpToolResult.text(
              'Started stopwatch ${(values.first as DBusUint32).value}.');
        }
        final seconds = (args.optionalInteger('hours', min: 0) ?? 0) * 3600 +
            (args.optionalInteger('minutes', min: 0) ?? 0) * 60 +
            (args.optionalInteger('seconds', min: 0) ?? 0);
        if (seconds <= 0) {
          throw const McpToolException('Give a duration, or stopwatch: true.');
        }
        final values = await shell.callShell(
          'StartTimer',
          [DBusUint64(seconds), DBusString(args.optionalString('label') ?? '')],
          'u',
        );
        return McpToolResult.text('Started timer '
            '${(values.first as DBusUint32).value} for '
            '${_formatDuration(seconds * 1000)}.');
      },
    ),
    McpTool(
      name: 'shell_control_timer',
      title: 'Pause, resume, reset or stop a timer',
      description: 'Acts on a timer by its id from shell_list_timers. '
          '"stop" removes it.',
      properties: {
        'id': Schema.integer('The timer.', min: 1),
        'operation': Schema.string('', oneOf: kControlTimerOperations),
      },
      required: ['id', 'operation'],
      handler: (args) async {
        final id = args.integer('id', min: 1);
        final operation = args.choice('operation', kControlTimerOperations);
        return done('TimerControl', [DBusUint32(id), DBusString(operation)],
            'Timer $id: $operation.');
      },
    ),
    // The todo board.
    McpTool(
      name: 'todo_list',
      title: 'List todo cards',
      description: 'The cards on the user\'s kanban board: id, column (inbox, '
          'todo, in_progress, finished, abandoned), title, body and due date.',
      properties: {
        'column': Schema.string('Only this column.', oneOf: kControlTodoColumns),
        'open_only': Schema.boolean(
            'Leave out finished and abandoned cards.'),
      },
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final column = args.has('column')
            ? args.choice('column', kControlTodoColumns)
            : null;
        final openOnly = args.optionalBool('open_only') ?? false;
        final values = await shell.callShell('ListTodos', const [], 'a(sssss)');
        return McpToolResult.json([
          for (final row in (values.first as DBusArray).children)
            if (column == null ||
                _str((row as DBusStruct).children[1]) == column)
              if (!openOnly ||
                  !const ['finished', 'abandoned']
                      .contains(_str((row as DBusStruct).children[1])))
                {
                  'id': _str((row as DBusStruct).children[0]),
                  'column': _str(row.children[1]),
                  'title': _str(row.children[2]),
                  if (_str(row.children[3]).isNotEmpty)
                    'body': _str(row.children[3]),
                  if (_str(row.children[4]).isNotEmpty)
                    'due': _str(row.children[4]),
                },
        ]);
      },
    ),
    McpTool(
      name: 'todo_add',
      title: 'Add a todo card',
      description: 'Puts a card at the top of a column on the user\'s board '
          '(default inbox).',
      properties: {
        'title': Schema.string('The card\'s title.'),
        'body': Schema.string('Notes; markdown-style checklists ("- [ ] …") '
            'are drawn as checkboxes.'),
        'column': Schema.string('Default inbox.', oneOf: kControlTodoColumns),
        'due': Schema.string('A due date, YYYY-MM-DD.'),
      },
      required: ['title'],
      handler: (args) async {
        final values = await shell.callShell(
          'AddTodo',
          [
            DBusString(args.string('title')),
            DBusString(args.optionalString('body') ?? ''),
            DBusString(args.has('column')
                ? args.choice('column', kControlTodoColumns)
                : 'inbox'),
            DBusString(args.optionalString('due') ?? ''),
          ],
          's',
        );
        return McpToolResult.json({'id': _str(values.first)});
      },
    ),
    McpTool(
      name: 'todo_move',
      title: 'Move a todo card',
      description: 'Moves a card to another column — "finished" to mark it '
          'done.',
      properties: {
        'id': Schema.string('From todo_list.'),
        'column': Schema.string('', oneOf: kControlTodoColumns),
      },
      required: ['id', 'column'],
      idempotent: true,
      handler: (args) async {
        final column = args.choice('column', kControlTodoColumns);
        return done('MoveTodo', [DBusString(args.string('id')), DBusString(column)],
            'Moved to $column.');
      },
    ),
    McpTool(
      name: 'todo_delete',
      title: 'Delete a todo card',
      description: 'Deletes a card outright. Moving it to "abandoned" keeps a '
          'record instead; prefer that unless the user asked for deletion.',
      properties: {'id': Schema.string('From todo_list.')},
      required: ['id'],
      destructive: true,
      handler: (args) async =>
          done('DeleteTodo', [DBusString(args.string('id'))], 'Deleted.'),
    ),
    McpTool(
      name: 'note_add',
      title: 'Add a sticky note',
      description: 'Adds a sticky note to the overview, where the user will '
          'find it the next time it opens, and to the board\'s search.',
      properties: {
        'title': Schema.string('Optional.'),
        'body': Schema.string('The note.'),
      },
      required: ['body'],
      handler: (args) async {
        final values = await shell.callShell(
          'AddNote',
          [
            DBusString(args.optionalString('title') ?? ''),
            DBusString(args.string('body')),
          ],
          's',
        );
        return McpToolResult.json({'id': _str(values.first)});
      },
    ),
    // Sound.
    McpTool(
      name: 'shell_get_volume',
      title: 'Read the volume',
      description: 'The default output\'s volume (0–100) and whether it is '
          'muted.',
      readOnly: true,
      idempotent: true,
      handler: (args) async {
        final values = await shell.callShell('GetVolume', const [], 'db');
        return McpToolResult.json({
          'volume': ((values[0] as DBusDouble).value * 100).round(),
          'muted': (values[1] as DBusBoolean).value,
        });
      },
    ),
    McpTool(
      name: 'shell_set_volume',
      title: 'Set the volume',
      description: 'Sets the default output\'s volume (0–100) and/or mutes '
          'or unmutes it.',
      properties: {
        'volume': Schema.number('0 to 100.', min: 0, max: 100),
        'muted': Schema.boolean(''),
      },
      idempotent: true,
      handler: (args) async {
        final volume = args.optionalNumber('volume', min: 0, max: 100);
        final muted = args.optionalBool('muted');
        if (volume == null && muted == null) {
          throw const McpToolException('Give "volume", "muted" or both.');
        }
        if (volume != null) {
          await shell.callShell('SetVolume', [DBusDouble(volume / 100)], '');
        }
        if (muted != null) {
          await shell.callShell('SetMuted', [DBusBoolean(muted)], '');
        }
        return McpToolResult.text([
          if (volume != null) 'Volume ${volume.round()}%.',
          if (muted != null) muted ? 'Muted.' : 'Unmuted.',
        ].join(' '));
      },
    ),
  ];
}

// --- media -------------------------------------------------------------------

List<McpTool> _mediaTools(ShellBusClient shell) => [
      McpTool(
        name: 'media_status',
        title: 'What is playing',
        description: 'Every media player (MPRIS): its name, whether it is '
            'playing, and the title, artist and album.',
        readOnly: true,
        idempotent: true,
        handler: (args) async => McpToolResult.json(await shell.mediaStatus()),
      ),
      McpTool(
        name: 'media_control',
        title: 'Control playback',
        description: 'Play, pause, skip or stop. Goes to the named player, or '
            'to the one playing (else the first).',
        properties: {
          'action': Schema.string('', oneOf: [
            'play',
            'pause',
            'play_pause',
            'stop',
            'next',
            'previous',
          ]),
          'player': Schema.string('A player from media_status; optional.'),
        },
        required: ['action'],
        handler: (args) async {
          final action = args.choice('action', const [
            'play',
            'pause',
            'play_pause',
            'stop',
            'next',
            'previous',
          ]);
          final player = await shell.mediaControl(action,
              player: args.optionalString('player'));
          return McpToolResult.text('Sent $action to $player.');
        },
      ),
    ];
