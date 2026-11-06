import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/capture/page_id.dart';
import 'package:hue_memory/vault/bot_inbox_writer.dart';
import 'package:hue_memory/vault/fake_vault_fs.dart';

class _FixedPageId extends PageId {
  _FixedPageId(this.id);
  final String id;
  @override
  String generate({DateTime? at}) => id;
}

void main() {
  test('writes image only into inbox folder', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('20261106-abcd'));
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    final result = await writer.writeImage(
      vault: vault,
      inboxFolder: 'inbox',
      imageBytes: bytes,
      capturedAt: DateTime.utc(2026, 11, 6, 8),
      imageExtension: 'jpg',
    );

    expect(result.folder, 'inbox');
    expect(result.fileName, '20261106-abcd.jpg');
    expect(result.relativePath, 'inbox/20261106-abcd.jpg');
    expect(await vault.exists(result.relativePath), isTrue);
    expect(await vault.readBytes(result.relativePath), bytes);
    // No markdown / canvas side effects.
    expect(await vault.list('inbox'), ['20261106-abcd.jpg']);
  });

  test('supports nested Bot/Inbox path', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('20261106-nest'));
    final result = await writer.writeImage(
      vault: vault,
      inboxFolder: 'Bot/Inbox',
      imageBytes: Uint8List.fromList([9]),
      capturedAt: DateTime.utc(2026, 11, 6),
      imageExtension: 'png',
    );
    expect(result.relativePath, 'Bot/Inbox/20261106-nest.png');
    expect(await vault.exists(result.relativePath), isTrue);
  });

  test('avoids silent overwrite on collision', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('20261106-same'));
    final first = Uint8List.fromList([1]);
    final second = Uint8List.fromList([2, 2]);

    final a = await writer.writeImage(
      vault: vault,
      inboxFolder: 'inbox',
      imageBytes: first,
      capturedAt: DateTime.utc(2026, 11, 6),
    );
    final b = await writer.writeImage(
      vault: vault,
      inboxFolder: 'inbox',
      imageBytes: second,
      capturedAt: DateTime.utc(2026, 11, 6),
    );

    expect(a.relativePath, 'inbox/20261106-same.jpg');
    expect(b.relativePath, 'inbox/20261106-same-2.jpg');
    expect(await vault.readBytes(a.relativePath), first);
    expect(await vault.readBytes(b.relativePath), second);
  });

  test('rejects parent-escape inbox folder', () async {
    final vault = FakeVaultFs();
    final writer = BotInboxWriter(pageIds: _FixedPageId('x'));
    expect(
      () => writer.writeImage(
        vault: vault,
        inboxFolder: '../outside',
        imageBytes: Uint8List.fromList([1]),
        capturedAt: DateTime.utc(2026, 11, 6),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
