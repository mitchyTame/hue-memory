import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/todoist/daily_todoist_plan.dart';
import 'package:hue_memory/todoist/ledger_linker.dart';
import 'package:hue_memory/todoist/todoist_ledger.dart';
import 'package:hue_memory/todoist/todoist_retry.dart';
import 'package:hue_memory/ui/confirm_shell.dart';
import 'package:hue_memory/ui/todoist_retry_card.dart';
import 'package:material_ui/material_ui.dart';

PendingCapture _capture() {
  final bytes = Uint8List.fromList(
    File('test/fixtures/pixel.png').readAsBytesSync(),
  );
  return PendingCapture(
    pageId: '20261127-p7k2',
    imageBytes: bytes,
    capturedAt: DateTime.utc(2026, 11, 27, 8),
    meaning: MeaningResult(
      detectedGlyph: '·',
      regions: [
        for (final (i, line) in [
          'high:',
          '- Call dentist',
          '- Pay rent',
          'done:',
          '- Ship release',
        ].indexed)
          OcrRegion(
            id: 'n$i',
            text: line,
            confidence: 0.9,
            bbox: [0.1, 0.1 + i * 0.1, 0.5, 0.08],
          ),
      ],
      pageGenre: 'task_list',
    ),
    symbolId: 'daily-tasks',
  );
}

void main() {
  Widget host(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('· daily shows a review checklist before anything is sent',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var sent = 0;
    var committed = 0;
    DailyTodoistPlan? sentPlan;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: _capture(),
          todoistPlanner: DailyTodoistPlanner(),
          onCommit: ({
            required symbolId,
            required title,
            required noteBody,
            required links,
            inkGhost = true,
            regions,
          }) async {
            committed++;
          },
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {
            sent++;
            sentPlan = plan;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(sent, 0);
    expect(committed, 0);
    expect(find.text('Review Todoist tasks'), findsOneWidget);
    expect(find.text('Send 3 to Todoist'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Call dentist'), findsOneWidget);
    expect(find.text('Mark done in Todoist'), findsOneWidget);

    // Skip "Pay rent", edit "Call dentist", make it P1.
    await tester.tap(find.byKey(const ValueKey('plan-include')).at(1));
    await tester.pumpAndSettle();
    expect(find.text('Send 2 to Todoist'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Call dentist'),
      'Call the dentist',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('plan-priority-P2')).first);
    await tester.pumpAndSettle();

    await tapText(tester, 'Send 2 to Todoist');

    expect(sent, 1);
    expect(committed, 0);
    expect(sentPlan!.effectiveCreates.map((c) => c.content), [
      'Call the dentist',
    ]);
    expect(sentPlan!.effectiveCreates.single.priority, 3);
    expect(sentPlan!.effectiveDone, ['Ship release']);
  });

  testWidgets('Edit nodes returns from the checklist without sending',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var sent = 0;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: _capture(),
          todoistPlanner: DailyTodoistPlanner(),
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {
            sent++;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit nodes'));
    await tester.pumpAndSettle();

    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Review Todoist tasks'), findsNothing);
    expect(sent, 0);
  });

  testWidgets('without a planner · daily still saves directly',
      (tester) async {
    var committed = 0;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: _capture(),
          onCommit: ({
            required symbolId,
            required title,
            required noteBody,
            required links,
            inkGhost = true,
            regions,
          }) async {
            committed++;
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(committed, 1);
  });

  testWidgets('retry card names the failure and the failed items',
      (tester) async {
    var retried = 0;
    var discarded = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: TodoistRetryCard(
            batches: [
              TodoistRetryBatch(
                createdAt: DateTime.utc(2026, 11, 27),
                items: const [
                  FailedTodoistItem(
                    kind: FailedItemKind.create,
                    content: 'Buy milk',
                    error: "Couldn't reach Todoist (check your connection)",
                  ),
                  FailedTodoistItem(
                    kind: FailedItemKind.done,
                    content: 'Ship release',
                    error: "Couldn't reach Todoist (check your connection)",
                  ),
                ],
              ),
            ],
            onRetry: () => retried++,
            onDiscard: () => discarded++,
          ),
        ),
      ),
    );

    expect(find.text('2 Todoist items did not send'), findsOneWidget);
    expect(find.textContaining('check your connection'), findsOneWidget);
    expect(find.text('• Buy milk'), findsOneWidget);
    expect(find.text('✓ Ship release'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('todoist-retry-button')));
    await tester.tap(find.byKey(const ValueKey('todoist-discard-button')));
    expect(retried, 1);
    expect(discarded, 1);
  });

  testWidgets('a re-capture shows update vs new and sends what is chosen',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final earlier = [
      LedgerEntry(
        todoistId: 'old-1',
        content: 'Call the dentist',
        pageId: 'earlier-page',
        createdAt: DateTime.utc(2026, 11, 26),
      ),
      LedgerEntry(
        todoistId: 'old-2',
        content: 'Pay rent',
        pageId: 'earlier-page',
        createdAt: DateTime.utc(2026, 11, 26),
      ),
    ];
    String? linkedFor;
    DailyTodoistPlan? sentPlan;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: _capture(),
          todoistPlanner: DailyTodoistPlanner(),
          todoistLinker: (plan, pageId) async {
            linkedFor = pageId;
            return LedgerLinker.link(plan, earlier, pageId: pageId);
          },
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {
            sentPlan = plan;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(linkedFor, '20261127-p7k2');
    expect(find.byKey(const ValueKey('plan-linked-banner')), findsOneWidget);
    expect(find.text('update'), findsNWidgets(2));
    expect(find.text('new'), findsNothing);
    expect(find.byKey(const ValueKey('plan-was')), findsOneWidget);
    expect(find.text('was: Call the dentist'), findsOneWidget);

    // Switch "Pay rent" to a new task.
    await tester.tap(find.byKey(const ValueKey('plan-link')).at(1));
    await tester.pumpAndSettle();
    expect(find.text('update'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);

    await tapText(tester, 'Send 3 to Todoist');
    expect(sentPlan!.effectiveCreates.map((c) => c.updateTodoistId), [
      'old-1',
      null,
    ]);
  });

  testWidgets('a first-time page shows no update/new badges', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: _capture(),
          todoistPlanner: DailyTodoistPlanner(),
          todoistLinker: (plan, pageId) async =>
              LedgerLinker.link(plan, const [], pageId: pageId),
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {},
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-link')), findsNothing);
    expect(find.byKey(const ValueKey('plan-linked-banner')), findsNothing);
  });

  testWidgets('retry card offers Recreate for tasks gone from Todoist',
      (tester) async {
    var recreated = 0;
    var retried = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: TodoistRetryCard(
            batches: [
              TodoistRetryBatch(
                createdAt: DateTime.utc(2026, 11, 27),
                items: const [
                  FailedTodoistItem(
                    kind: FailedItemKind.update,
                    content: 'Call dentist today',
                    error: 'Task was deleted or completed in Todoist',
                    updateTodoistId: 'old-1',
                    remoteMissing: true,
                  ),
                ],
              ),
            ],
            onRetry: () => retried++,
            onRecreate: () => recreated++,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('todoist-missing-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('todoist-retry-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('todoist-recreate-button')));
    expect(recreated, 1);
    expect(retried, 0);
  });

  testWidgets('a "| HH:MM" task shows its due time and it can be removed',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final bytes = Uint8List.fromList(
      File('test/fixtures/pixel.png').readAsBytesSync(),
    );
    final capture = PendingCapture(
      pageId: '20261127-bbbb',
      imageBytes: bytes,
      capturedAt: DateTime.utc(2026, 11, 27, 8),
      meaning: MeaningResult(
        detectedGlyph: '·',
        regions: [
          for (final (i, line) in ['high:', '- bolt | 16:50', '- Call mum'].indexed)
            OcrRegion(
              id: 'n$i',
              text: line,
              confidence: 0.9,
              bbox: [0.1, 0.1 + i * 0.1, 0.5, 0.08],
            ),
        ],
        pageGenre: 'task_list',
      ),
      symbolId: 'daily-tasks',
    );
    DailyTodoistPlan? sentPlan;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: capture,
          todoistPlanner: DailyTodoistPlanner(
            clock: () => DateTime(2026, 11, 27, 9),
          ),
          todoistLinker: (plan, pageId) async =>
              LedgerLinker.link(plan, const [], pageId: pageId),
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {
            sentPlan = plan;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'bolt'), findsOneWidget);
    expect(find.text('due Fri 27 Nov 16:50'), findsOneWidget);
    // "Call mum" has nothing written next to it: no due chip.
    expect(find.byKey(const ValueKey('plan-due')), findsOneWidget);
    expect(find.byKey(const ValueKey('plan-link-checked')), findsOneWidget);

    await tester.tap(find.byTooltip('No due date'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-due')), findsNothing);

    await tapText(tester, 'Send 2 to Todoist');
    expect(sentPlan!.effectiveCreates.map((c) => c.dueDate), [null, null]);
  });

  PendingCapture lines(List<String> text) {
    final bytes = Uint8List.fromList(
      File('test/fixtures/pixel.png').readAsBytesSync(),
    );
    return PendingCapture(
      pageId: '20261127-cccc',
      imageBytes: bytes,
      capturedAt: DateTime.utc(2026, 11, 27, 8),
      meaning: MeaningResult(
        detectedGlyph: '·',
        regions: [
          for (final (i, line) in text.indexed)
            OcrRegion(
              id: 'n$i',
              text: line,
              confidence: 0.9,
              bbox: [0.1, 0.1 + i * 0.05, 0.5, 0.04],
            ),
        ],
        pageGenre: 'task_list',
      ),
      symbolId: 'daily-tasks',
    );
  }

  testWidgets('dates from the page show before sending and can be edited',
      (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    DailyTodoistPlan? sentPlan;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: lines([
            'home:',
            '- call mum tomorrow @ 4pm',
            '- pay rent every 1st',
            '- Buy milk',
          ]),
          todoistPlanner: DailyTodoistPlanner(
            clock: () => DateTime(2026, 11, 27, 9),
          ),
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {
            sentPlan = plan;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'call mum'), findsOneWidget);
    expect(find.text('due Sat 28 Nov 16:00'), findsOneWidget);
    expect(find.text('Todoist will read: every 1st'), findsOneWidget);
    // "Buy milk" has no date on paper: no due, only an "add" chip.
    expect(find.byKey(const ValueKey('plan-due')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('plan-add-due')), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);

    await tapText(tester, 'due Sat 28 Nov 16:00');
    await tester.enterText(
      find.byKey(const ValueKey('plan-due-field')),
      'Fri @ 9am',
    );
    await tester.tap(find.byKey(const ValueKey('plan-due-save')));
    await tester.pumpAndSettle();
    expect(find.text('due Fri 27 Nov 09:00'), findsOneWidget);

    await tapText(tester, '+ due');
    await tester.enterText(
      find.byKey(const ValueKey('plan-due-field')),
      'every other week',
    );
    await tester.tap(find.byKey(const ValueKey('plan-due-save')));
    await tester.pumpAndSettle();
    expect(find.text('Todoist will read: every other week'), findsOneWidget);

    await tapText(tester, 'Send 3 to Todoist');
    final sent = sentPlan!.effectiveCreates;
    expect(sent[0].dueDate, DateTime(2026, 11, 27, 9));
    expect(sent[1].dueString, 'every 1st');
    expect(sent[2].dueString, 'every other week');
  });

  testWidgets('ticked items show what Todoist already holds', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    DailyTodoistPlan? sentPlan;
    await tester.pumpWidget(
      host(
        ConfirmShell(
          capture: lines([
            'errands:',
            '- ~~bolt~~ | 16:50',
            '- ✓ Post office',
            '- [x] Pharmacy',
            '- Gym',
          ]),
          todoistPlanner: DailyTodoistPlanner(
            clock: () => DateTime(2026, 11, 27, 9),
          ),
          todoistLinker: (plan, pageId) async {
            final linked = LedgerLinker.link(
              plan,
              [
                for (final (id, text) in [
                  ('t1', 'bolt'),
                  ('t2', 'Post office'),
                  ('t3', 'Pharmacy'),
                  ('t4', 'Gym'),
                ])
                  LedgerEntry(
                    todoistId: id,
                    content: text,
                    createdAt: DateTime(2026, 11, 27, 8),
                    pageId: 'earlier',
                    pageDay: '2026-11-27',
                  ),
              ],
              pageId: pageId,
            );
            return linked.withRemoteStates({
              't1': RemoteState.open,
              't2': RemoteState.completed,
              't3': RemoteState.gone,
              't4': RemoteState.completed,
            });
          },
          onSendTodoist: ({
            required title,
            required noteBody,
            required regions,
            required plan,
          }) async {
            sentPlan = plan;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Will complete: bolt'), findsOneWidget);
    expect(find.text('Already completed in Todoist'), findsOneWidget);
    expect(find.text('No longer in Todoist'), findsOneWidget);
    expect(
      find.text('Already completed in Todoist (tick to reopen it)'),
      findsOneWidget,
    );

    await tapText(tester, 'Send 1 to Todoist');
    expect(sentPlan!.effectiveDoneTargets.map((d) => d.todoistId), ['t1']);
    expect(sentPlan!.effectiveCreates, isEmpty);
  });
}
