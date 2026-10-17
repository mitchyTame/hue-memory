import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/camera/camera_capture.dart';
import 'package:hue_memory/camera/camera_session.dart';
import 'package:hue_memory/camera/live_camera_shell.dart';
import 'package:hue_memory/theme/app_theme.dart';
import 'package:hue_memory/theme/memory_hues.dart';

void main() {
  setUp(() => AppTheme.skipGoogleFonts = true);
  tearDown(() => AppTheme.skipGoogleFonts = false);

  testWidgets('shutter pops CaptureResult from fake session', (tester) async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    CaptureResult? popped;

    // Portrait phone — shutter sits bottom-center.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame'), findsOneWidget);
    expect(find.text('Fake preview'), findsOneWidget);
    expect(find.text('glyph'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Shutter'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.imageBytes, bytes);
    expect(popped!.imageExtension, 'jpg');
  });

  testWidgets('close cancels without a result', (tester) async {
    CaptureResult? popped;
    var completed = false;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(popped, isNull);
  });

  testWidgets('camera chrome uses multi-stop hue frame (not flat ink)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LiveCameraShell(
          sessionFactory: () async => FakeCameraSession(
            imageBytes: Uint8List.fromList([1]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, MemoryHues.fieldDeep);

    final gradients = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.gradient)
        .whereType<LinearGradient>()
        .toList();

    expect(gradients, isNotEmpty);
    final allColors = gradients.expand((g) => g.colors).toSet();
    // Shared atmosphere — ink family only (no mustard/copper carnival).
    expect(allColors, contains(MemoryHues.fieldDeep));
    expect(allColors, contains(MemoryHues.fieldTeal));
    expect(allColors, contains(MemoryHues.fieldLift));
    expect(allColors, isNot(contains(const Color(0xFFC4923A))));
    expect(allColors, isNot(contains(const Color(0xFFC4785C))));
    final atmosphere = gradients.any(
      (g) =>
          g.colors.length >= 3 &&
          g.colors.contains(MemoryHues.fieldDeep) &&
          g.colors.contains(MemoryHues.fieldTeal),
    );
    expect(atmosphere, isTrue);
  });

  testWidgets('landscape shutter rail is on-screen and tappable', (tester) async {
    CaptureResult? popped;

    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<CaptureResult>(
                      MaterialPageRoute(
                        builder: (_) => LiveCameraShell(
                          sessionFactory: () async => FakeCameraSession(
                            imageBytes: Uint8List.fromList([9]),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Frame page'), findsOneWidget);
    final shutterRect = tester.getRect(find.bySemanticsLabel('Shutter'));
    expect(shutterRect.right, lessThanOrEqualTo(800.0 + 0.5));
    expect(shutterRect.left, greaterThan(400)); // right rail

    await tester.tap(find.bySemanticsLabel('Shutter'));
    await tester.pumpAndSettle();
    expect(popped, isNotNull);
  });
}
