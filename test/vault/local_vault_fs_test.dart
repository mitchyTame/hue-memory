import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/commit_pipeline.dart';
import 'package:hue_memory/vault/local_vault_fs.dart';
import 'package:hue_memory/capture/pending_capture.dart';
import 'package:hue_memory/ocr/mock_ocr_client.dart';
import 'package:hue_memory/ocr/ocr_client.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late LocalVaultFs vault;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('hue-memory-vault-');
    vault = LocalVaultFs(temp);
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  test('writes and reads text under vault root', () async {
    await vault.writeText('inbox/hello.md', '# hi\n');
    expect(await vault.exists('inbox/hello.md'), isTrue);
    expect(await vault.readText('inbox/hello.md'), '# hi\n');
    expect(File(p.join(temp.path, 'inbox', 'hello.md')).existsSync(), isTrue);
  });

  test('rejects path escape', () async {
    expect(
      () => vault.writeText('../outside.md', 'x'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('rejects content:// tree URIs', () {
    expect(
      () => LocalVaultFs(
        Directory(
          'content://com.android.externalstorage.documents/tree/primary%3AVault',
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('overwrite via temp+rename leaves final path only', () async {
    await vault.writeText('inbox/note.md', 'one');
    await vault.writeText('inbox/note.md', 'two');
    expect(await vault.readText('inbox/note.md'), 'two');
    final leftovers = temp
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.contains('.hue-tmp-'));
    expect(leftovers, isEmpty);
  });

  test('commit pipeline persists markdown + raw image on disk', () async {
    final pipeline = CommitPipeline(vault: vault);
    final capture = PendingCapture(
      pageId: '20261016-disk',
      imageBytes: Uint8List.fromList([1, 2, 3, 4]),
      capturedAt: DateTime.utc(2026, 10, 16),
      meaning: MeaningResult(
        detectedGlyph: '∼',
        regions: MockOcrClient.defaultFleetingRegions,
      ),
      imageExtension: 'png',
    );

    final result = await pipeline.commit(
      CommitInput(
        capture: capture,
        symbolId: 'fleeting',
        title: 'Disk note',
        noteBody: 'Persisted',
      ),
    );

    expect(File(p.join(temp.path, result.rawImagePath)).existsSync(), isTrue);
    expect(File(p.join(temp.path, result.notePath!)).existsSync(), isTrue);
    final md = await File(p.join(temp.path, result.notePath!)).readAsString();
    expect(md, contains('Persisted'));
  });
}
