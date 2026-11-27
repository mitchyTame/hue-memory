import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/todoist/daily_todoist_parser.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';

DailyTodoistPlan _treePlan() {
  return DailyTodoistPlan.fromParse(
    const DailyTodoistParseResult(
      creates: [
        DailyTodoistCreate(
          content: 'Plan trip',
          label: 'home',
          priority: 4,
          nodeId: 'a',
        ),
        DailyTodoistCreate(
          content: 'Book flights',
          label: 'home',
          nodeId: 'b',
          parentNodeId: 'a',
        ),
        DailyTodoistCreate(
          content: 'Compare prices',
          label: 'home',
          nodeId: 'c',
          parentNodeId: 'b',
        ),
        DailyTodoistCreate(
          content: 'Buy milk',
          label: 'shopping',
          nodeId: 'd',
        ),
      ],
      done: ['Ship release'],
      sectionLabels: ['home', 'shopping', 'ideas'],
    ),
  );
}

void main() {
  test('fromParse keys items and includes everything by default', () {
    final plan = _treePlan();
    expect(plan.creates.map((t) => t.key), ['c0', 'c1', 'c2', 'c3']);
    expect(plan.done.single.key, 'd0');
    expect(plan.includedCount, 5);
    expect(plan.effectiveCreates.map((c) => c.content), [
      'Plan trip',
      'Book flights',
      'Compare prices',
      'Buy milk',
    ]);
    expect(plan.effectiveDone, ['Ship release']);
    expect(plan.depthOf(0), 0);
    expect(plan.depthOf(2), 2);
  });

  test('skipping a task also skips its subtasks; re-including is per item', () {
    var plan = _treePlan().setTaskIncluded(1, false);
    expect(plan.creates.map((t) => t.included), [true, false, false, true]);
    expect(plan.effectiveCreates.map((c) => c.content), [
      'Plan trip',
      'Buy milk',
    ]);

    plan = plan.setTaskIncluded(2, true);
    final sent = plan.effectiveCreates;
    expect(sent.map((c) => c.content), [
      'Plan trip',
      'Compare prices',
      'Buy milk',
    ]);
    // Parent "Book flights" is skipped, so the subtask is promoted to a
    // top-level task that still carries its section label.
    expect(sent[1].parentNodeId, isNull);
    expect(sent[1].label, 'home');
  });

  test('edits change text and priority; P4 clears priority', () {
    var plan = _treePlan()
        .setTaskContent(3, '  Buy oat milk ')
        .setTaskPriority(3, 3)
        .setTaskPriority(0, null);
    final sent = plan.effectiveCreates;
    expect(sent.last.content, 'Buy oat milk');
    expect(sent.last.priority, 3);
    expect(sent.first.priority, isNull);

    plan = plan.setDoneContent(0, 'Ship v2').setDoneIncluded(0, true);
    expect(plan.effectiveDone, ['Ship v2']);
  });

  test('blank text is not sent; nothing selected means no work', () {
    var plan = _treePlan().setTaskContent(3, '   ');
    expect(plan.effectiveCreates.map((c) => c.content), isNot(contains('')));
    expect(plan.effectiveCreates, hasLength(3));

    plan = DailyTodoistPlan.fromParse(
      const DailyTodoistParseResult(
        creates: [DailyTodoistCreate(content: 'Only', label: 'x')],
        sectionLabels: ['x'],
      ),
    ).setTaskIncluded(0, false);
    expect(plan.includedCount, 0);
    expect(plan.hasWork, isFalse);
    expect(plan.effectiveSectionLabels, isEmpty);
  });

  test('labels follow included tasks; label-only headings are kept', () {
    final plan = _treePlan().setTaskIncluded(3, false);
    expect(plan.labelOnlySections, ['ideas']);
    expect(plan.effectiveSectionLabels, ['home', 'ideas']);
  });

  test('planner reads section markdown without any network', () {
    final plan = DailyTodoistPlanner().plan(markdown: '''
high:
- Call dentist
done:
- Ship release
''');
    expect(plan.creates.single.create.label, 'high');
    expect(plan.creates.single.priority, 4);
    expect(plan.done.single.content, 'Ship release');
  });
}
