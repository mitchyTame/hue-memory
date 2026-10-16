import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/links/thread_tick.dart';
import 'package:hue_memory/writers/link_writer.dart';

void main() {
  test('detects › and ascii >', () {
    expect(ThreadTick.detectedIn('∼›'), isTrue);
    expect(ThreadTick.detectedIn('F>'), isTrue);
    expect(ThreadTick.detectedIn('∼'), isFalse);
  });

  test('stripFromGlyph leaves type mark', () {
    expect(ThreadTick.stripFromGlyph('∼›'), '∼');
    expect(ThreadTick.stripFromGlyph('△>'), '△');
  });

  test('mergePrevious prepends once', () {
    const prev = LinkPick(
      targetPath: 'fleeting/20261016-aaaa-wave',
      displayTitle: 'Earlier wave',
    );
    final once = ThreadTick.mergePrevious(previous: prev);
    expect(once, hasLength(1));
    final twice = ThreadTick.mergePrevious(previous: prev, existing: once);
    expect(twice, hasLength(1));
  });
}
