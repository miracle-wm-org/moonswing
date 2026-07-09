import 'package:flutter_test/flutter_test.dart';
import 'package:toml/toml.dart';

/// Verifies the mechanism the settings ConfigStore relies on: mutating a parsed
/// config map and re-encoding it with `TomlDocument.fromMap(...).toString()`
/// produces valid TOML that round-trips back to the same structure — including
/// nested tables, an array-of-tables (`[[background.entries]]`), and list
/// values.
void main() {
  test('config map encodes to TOML and round-trips', () {
    final map = <String, dynamic>{
      'theme': {
        'accent': '#853953',
        'divider': '#33F3F4F4',
        'font': 'Ubuntu Sans',
      },
      'panels': {
        'top': {
          'height': 32,
          'padding_horizontal': 40,
          'anchor': 'top',
          'layer': 'top',
          'layout': {
            'left': ['workspaces'],
            'center': ['clock'],
            'right': ['sound_control', 'system_tray', 'battery'],
          },
        },
      },
      'modules': {
        'weather': {'unit': 'celsius', 'refresh_minutes': 10},
        'media_player': {'max_text_width': 200.0},
        'clock': {'show_date': true},
        'system_tray': {
          'icon_size': 16.0,
          'hidden_items': ['Discord', 'Steam'],
        },
      },
      'background': {
        'fit': 'fill',
        'interval_minutes': 5,
        'entries': [
          {'path': '/home/u/a.jpg', 'shown': true},
          {'path': '/home/u/b.jpg', 'shown': false},
        ],
      },
    };

    final toml = TomlDocument.fromMap(map).toString();
    final reparsed = TomlDocument.parse(toml).toMap();

    expect(reparsed['theme']['accent'], '#853953');
    expect(reparsed['theme']['divider'], '#33F3F4F4');
    expect(reparsed['panels']['top']['height'], 32);
    expect(reparsed['panels']['top']['layout']['right'],
        ['sound_control', 'system_tray', 'battery']);
    expect(reparsed['modules']['weather']['unit'], 'celsius');
    expect(reparsed['modules']['media_player']['max_text_width'], 200.0);
    expect(reparsed['modules']['clock']['show_date'], true);
    expect(reparsed['modules']['system_tray']['hidden_items'],
        ['Discord', 'Steam']);
    expect(reparsed['background']['interval_minutes'], 5);
    final entries = reparsed['background']['entries'] as List;
    expect(entries.length, 2);
    expect(entries[1]['path'], '/home/u/b.jpg');
    expect(entries[1]['shown'], false);
  });

  test('empty and single-key maps encode without error', () {
    expect(TomlDocument.fromMap(<String, dynamic>{}).toString(), isA<String>());
    final one = TomlDocument.fromMap({
      'theme': {'accent': '#FFFFFF'}
    }).toString();
    expect(TomlDocument.parse(one).toMap()['theme']['accent'], '#FFFFFF');
  });
}
