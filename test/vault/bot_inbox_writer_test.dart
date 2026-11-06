import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/page_id.dart';
import 'package:hue_memory/vault/bot_inbox_writer.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';
import 'package:hue_memory/writers/canvas_writer.dart';

class _FixedPageId extends PageId {
  _FixedPageId(this.id);
  final String id;
  @override
  String generate({DateTime? at}) => id;
}

void main() {
  test('writes canvas + raw under captures/raw, not orphan inbox jpg', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('20261106-abcd'));
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final result = await writer.writeCanvas(
      vault: vault,
      inboxFolder: 'inbox',
      imageBytes: bytes,
      capturedAt: DateTime(2026, 11, 6, 8),
      imageExtension: 'jpg',
      textNodes: const [
        CanvasNode(
          id: 'n1',
          type: 'text',
          text: '[TASK] Call dentist',
          x: 0,
          y: 0,
          width: 200,
          height: 80,
        ),
      ],
    );

    expect(result.folder, 'inbox');
    expect(result.fileName, '2026-11-06.canvas');
    expect(result.relativePath, 'inbox/2026-11-06.canvas');
    expect(result.rawImagePath, 'captures/raw/20261106-abcd.jpg');
    expect(await vault.exists(result.relativePath), isTrue);
    expect(await vault.exists(result.rawImagePath), isTrue);
    expect(await vault.readBytes(result.rawImagePath), bytes);

    final canvas = jsonDecode(await vault.readText(result.relativePath))
        as Map<String, dynamic>;
    final nodes = (canvas['nodes'] as List).cast<Map<String, dynamic>>();
    final fileNode = nodes.firstWhere((n) => n['type'] == 'file');
    expect(fileNode['file'], result.rawImagePath);
    expect(
      nodes.any((n) => '${n['text']}'.contains('[TASK] Call dentist')),
      isTrue,
    );
    // No orphan image as the sole inbox artifact.
    expect(await vault.list('inbox'), ['2026-11-06.canvas']);
  });

  test('date stem collision renames to YYYY-MM-DD-n.canvas', () async {
    final vault = FakeVaultFs();
    final at = DateTime(2026, 11, 6);

    Future<BotInboxWriteResult> writeOnce(Uint8List bytes, String pageId) {
      return BotInboxWriter(pageIds: _FixedPageId(pageId)).writeCanvas(
        vault: vault,
        inboxFolder: 'inbox',
        imageBytes: bytes,
        capturedAt: at,
        textNodes: const [
          CanvasNode(
            id: 'n1',
            type: 'text',
            text: '[NOTE] scrap',
            x: 0,
            y: 0,
            width: 160,
            height: 64,
          ),
        ],
      );
    }

    final a = await writeOnce(Uint8List.fromList([1]), '20261106-a');
    final b = await writeOnce(Uint8List.fromList([2, 2]), '20261106-b');

    expect(a.fileName, '2026-11-06.canvas');
    expect(b.fileName, '2026-11-06-2.canvas');
    expect(a.relativePath, 'inbox/2026-11-06.canvas');
    expect(b.relativePath, 'inbox/2026-11-06-2.canvas');
    expect(await vault.exists(a.rawImagePath), isTrue);
    expect(await vault.exists(b.rawImagePath), isTrue);
  });

  test('uniqueRelativePath collision helper', () async {
    final vault = FakeVaultFs(
      seed: {
        'inbox/2026-11-06.canvas': '{}',
        'inbox/2026-11-06-2.canvas': '{}',
      },
    );
    final path = await BotInboxWriter.uniqueRelativePath(
      vault: vault,
      folder: 'inbox',
      stem: '2026-11-06',
      extension: 'canvas',
    );
    expect(path, 'inbox/2026-11-06-3.canvas');
  });

  test('supports nested Bot/Inbox path', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('20261106-nest'));
    final result = await writer.writeCanvas(
      vault: vault,
      inboxFolder: 'Bot/Inbox',
      imageBytes: Uint8List.fromList([9]),
      capturedAt: DateTime(2026, 11, 6),
      imageExtension: 'png',
      textNodes: const [
        CanvasNode(
          id: 'n1',
          type: 'text',
          text: '[SUMMARY] nested',
          x: 0,
          y: 0,
          width: 180,
          height: 64,
        ),
      ],
    );
    expect(result.relativePath, 'Bot/Inbox/2026-11-06.canvas');
    expect(result.rawImagePath, 'captures/raw/20261106-nest.png');
    expect(await vault.exists(result.relativePath), isTrue);
  });

  test('rejects parent-escape inbox folder', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('x'));
    expect(
      () => writer.writeCanvas(
        vault: vault,
        inboxFolder: '../outside',
        imageBytes: Uint8List.fromList([1]),
        capturedAt: DateTime(2026, 11, 6),
        textNodes: const [
          CanvasNode(
            id: 'n1',
            type: 'text',
            text: '[NOTE] x',
            x: 0,
            y: 0,
            width: 100,
            height: 40,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
