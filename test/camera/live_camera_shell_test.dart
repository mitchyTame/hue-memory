import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/camera/camera_capture.dart';
import 'package:hue_memory/camera/camera_session.dart';
import 'package:hue_memory/camera/live_camera_shell.dart';
import 'package:hue_memory/theme/app_theme.dart';

void main() {
  setUp(() => AppTheme.skipGoogleFonts = true);
  tearDown(() => AppTheme.skipGoogleFonts = false);

  testWidgets('shutter pops CaptureResult from fake session', (tester) async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    CaptureResult? popped;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<CaptureResult>(
                    MaterialPageRoute(
                      builder: (_) => LiveCameraShell(
                        sessionFactory: () async => FakeCameraSession(
                          imageBytes: bytes,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Frame the page'), findsOneWidget);
    expect(find.text('Fake preview'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Shutter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(popped, isNotNull);
    expect(popped!.imageBytes, bytes);
    expect(popped!.imageExtension, 'jpg');
  });

  testWidgets('close cancels without a result', (tester) async {
    CaptureResult? popped;
    var completed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<CaptureResult>(
                    MaterialPageRoute(
                      builder: (_) => LiveCameraShell(
                        sessionFactory: () async => FakeCameraSession(
                          imageBytes: Uint8List.fromList([1]),
                        ),
                      ),
                    ),
                  );
                  completed = true;
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(completed, isTrue);
    expect(popped, isNull);
  });
}
