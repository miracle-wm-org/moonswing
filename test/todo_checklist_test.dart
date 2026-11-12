import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/todo/todo_checklist.dart';

void main() {
  group('parseTodoBody', () {
    test('takes the task-list lines out of the text, in order', () {
      final parsed = parseTodoBody(
        'Notes first.\n\n- [x] Draft it\n- [ ] Send it\n',
      );
      expect(parsed.description, 'Notes first.');
      expect(parsed.checklist, const [
        TodoCheckItem(text: 'Draft it', done: true),
        TodoCheckItem(text: 'Send it'),
      ]);
    });

    test('reads what other clients write, wherever they put it', () {
      final parsed = parseTodoBody(
        '* [X] Shouted\r\nAbove\r\n\r\n  + [ ] Nested  \r\n\r\n\r\nBelow',
      );
      expect(parsed.checklist, const [
        TodoCheckItem(text: 'Shouted', done: true),
        TodoCheckItem(text: 'Nested'),
      ]);
      // The gap the steps leave closes to one blank line.
      expect(parsed.description, 'Above\n\nBelow');
    });

    test('a box with no step, or no box, is text', () {
      const body = '- [ ]\n- [] nope\n-[x] nor this\n- [y] or this\n- plain';
      final parsed = parseTodoBody(body);
      expect(parsed.checklist, isEmpty);
      expect(parsed.description, body);
    });

    test('a body with no checklist is its own description', () {
      expect(parseTodoBody('  Just text  ').description, 'Just text');
      expect(parseTodoBody('').checklist, isEmpty);
    });
  });

  group('composeTodoBody', () {
    test('puts the steps after the text, and reads back', () {
      const steps = [
        TodoCheckItem(text: 'One', done: true),
        TodoCheckItem(text: 'Two'),
      ];
      final body = composeTodoBody('Text\n', steps);
      expect(body, 'Text\n\n- [x] One\n- [ ] Two');
      final parsed = parseTodoBody(body);
      expect(parsed.description, 'Text');
      expect(parsed.checklist, steps);
    });

    test('a step is one line, and an empty one is left out', () {
      expect(
        composeTodoBody('', const [
          TodoCheckItem(text: 'Two\nlines'),
          TodoCheckItem(text: '   '),
        ]),
        '- [ ] Two lines',
      );
      expect(composeTodoBody('Only text  ', const []), 'Only text');
    });
  });

  test('setCheckedInBody ticks one step where it stands', () {
    const body = 'Intro\n* [ ] A\r\nMiddle\n  - [x] B';
    expect(
      setCheckedInBody(body, 0, done: true),
      'Intro\n* [x] A\r\nMiddle\n  - [x] B',
    );
    expect(
      setCheckedInBody(body, 1, done: false),
      'Intro\n* [ ] A\r\nMiddle\n  - [ ] B',
    );
    expect(setCheckedInBody(body, 2, done: true), isNull);
  });

  test('untickAllInBody unticks every step and nothing else', () {
    expect(
      untickAllInBody('Text [x]\n- [x] A\n* [X] B\n- [ ] C'),
      'Text [x]\n- [ ] A\n* [ ] B\n- [ ] C',
    );
  });

  test('checklistProgress counts the ticked steps', () {
    expect(checklistProgress(const []), (done: 0, total: 0, fraction: 0.0));
    final p = checklistProgress(const [
      TodoCheckItem(text: 'a', done: true),
      TodoCheckItem(text: 'b'),
      TodoCheckItem(text: 'c', done: true),
      TodoCheckItem(text: 'd'),
    ]);
    expect((p.done, p.total, p.fraction), (2, 4, 0.5));
  });
}
