// A card's checklist, kept in its body as a Markdown task list.
//
// The body is the one field of a card a CalDAV task list carries as free text
// (`DESCRIPTION`), so a checklist written into it travels with the card to the
// phone and back, and every other client shows it as the lines it is:
//
//     Notes about the job.
//
//     - [x] Draft it
//     - [ ] Send it
//
// The board parses those lines out to draw them as a checklist, and draws the
// rest as the description. Nothing about a checklist is stored anywhere else,
// so there is no second copy to drift from the first, and the sync's three-way
// merge sees a tick as the edit to the notes that it is.
//
// Flutter-free and I/O-free, for `test/todo_checklist_test.dart`.

/// One line of a card's checklist.
class TodoCheckItem {
  const TodoCheckItem({required this.text, this.done = false});

  final String text;
  final bool done;

  TodoCheckItem copyWith({String? text, bool? done}) =>
      TodoCheckItem(text: text ?? this.text, done: done ?? this.done);

  @override
  bool operator ==(Object other) =>
      other is TodoCheckItem && other.text == text && other.done == done;

  @override
  int get hashCode => Object.hash(text, done);

  @override
  String toString() => 'TodoCheckItem(${done ? 'x' : ' '} $text)';
}

/// A body split into what the board draws as text and what it draws as a
/// checklist.
typedef TodoBody = ({String description, List<TodoCheckItem> checklist});

/// A task-list line: a `-`, `*` or `+` bullet, a box of one space or an `x`,
/// and some text. Indented ones count too, since some clients nest them; a box
/// with nothing after it is not a step and stays in the text.
final RegExp _kCheckLine = RegExp(r'^(\s*[-*+]\s+\[)([ xX])(\]\s+)(\S.*?)\s*$');

/// Two or more blank lines in a row, which taking a checklist out from the
/// middle of the text would otherwise leave behind.
final RegExp _kBlankRun = RegExp(r'\n[ \t]*\n(?:[ \t]*\n)+');

/// The lines of [body], each without a trailing `\r`, so a body that arrived
/// with Windows line ends parses as one that did not.
List<String> _lines(String body) => [
  for (final line in body.split('\n'))
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
];

/// [body] as the board draws it: its task-list lines as a checklist, in the
/// order they appear, and the rest as the description, trimmed.
TodoBody parseTodoBody(String body) {
  final checklist = <TodoCheckItem>[];
  final text = <String>[];
  for (final line in _lines(body)) {
    final match = _kCheckLine.firstMatch(line);
    if (match == null) {
      text.add(line);
    } else {
      checklist.add(
        TodoCheckItem(text: match.group(4)!, done: match.group(2) != ' '),
      );
    }
  }
  final description = text.join('\n').replaceAll(_kBlankRun, '\n\n').trim();
  return (description: description, checklist: checklist);
}

/// The body for [description] and [checklist]: the text, a blank line, then
/// one `- [ ]` or `- [x]` line per step.
///
/// A step's text is made one line — a line break inside it would end the
/// line — and a step with no text is left out, as it would not parse back.
String composeTodoBody(String description, List<TodoCheckItem> checklist) {
  final steps = [
    for (final step in checklist)
      if (step.text.replaceAll(RegExp(r'\s+'), ' ').trim() case final text
          when text.isNotEmpty)
        '- [${step.done ? 'x' : ' '}] $text',
  ];
  final text = description.trimRight();
  if (steps.isEmpty) return text;
  if (text.isEmpty) return steps.join('\n');
  return '$text\n\n${steps.join('\n')}';
}

/// [body] with step [index] of its checklist ticked or unticked, and nothing
/// else about it changed: its place among the text, its bullet, its spacing.
/// Null when there is no such step.
String? setCheckedInBody(String body, int index, {required bool done}) {
  final lines = body.split('\n');
  var seen = 0;
  for (var i = 0; i < lines.length; i++) {
    final match = _kCheckLine.firstMatch(lines[i]);
    if (match == null) continue;
    if (seen++ != index) continue;
    final box = match.group(1)!.length;
    lines[i] =
        '${lines[i].substring(0, box)}${done ? 'x' : ' '}'
        '${lines[i].substring(box + 1)}';
    return lines.join('\n');
  }
  return null;
}

/// [body] with every step of its checklist unticked, for a recurring card's
/// next copy: the same steps, the job to do again.
String untickAllInBody(String body) => [
  for (final line in body.split('\n'))
    if (_kCheckLine.firstMatch(line) case final match?)
      '${match.group(1)} ${line.substring(match.group(1)!.length + 1)}'
    else
      line,
].join('\n');

/// How far through [checklist] a card is: how many steps are ticked of how
/// many there are, and that as a fraction — 0 for an empty list, which has
/// nothing to be through.
({int done, int total, double fraction}) checklistProgress(
  List<TodoCheckItem> checklist,
) {
  final total = checklist.length;
  final done = checklist.where((c) => c.done).length;
  return (done: done, total: total, fraction: total == 0 ? 0 : done / total);
}
