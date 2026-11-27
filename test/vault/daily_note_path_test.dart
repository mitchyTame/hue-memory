import 'package:flutter_test/flutter_test.dart';
import 'package:hue_memory/vault/daily_note_path.dart';

void main() {
  const resolver = DailyNotePathResolver();
  final date = DateTime(2026, 10, 16);

  test('YYYY-MM-DD + Organising/Daily folder', () {
    const settings = DailyNoteSettings(
      folder: 'Organising/Daily',
      format: 'YYYY-MM-DD',
    );
    expect(
      resolver.resolve(settings, date: date),
      'Organising/Daily/2026-10-16.md',
    );
  });

  test('default folder is Organising/Daily', () {
    expect(
      const DailyNoteSettings().folder,
      'Organising/Daily',
    );
  });

  test('nested format with empty folder', () {
    const settings = DailyNoteSettings(
      folder: '',
      format: 'YYYY/MM/YYYY-MM-DD',
    );
    expect(
      resolver.resolve(settings, date: date),
      '2026/10/2026-10-16.md',
    );
  });

  test('literal prefix and month name', () {
    const settings = DailyNoteSettings(
      folder: '',
      format: '[Daily]/YYYY/MMMM/YYYY-MM-DD',
    );
    expect(
      resolver.resolve(settings, date: date),
      'Daily/2026/October/2026-10-16.md',
    );
  });

  test('does not double-append .md when format includes it', () {
    const settings = DailyNoteSettings(
      folder: 'Journal',
      format: 'YYYY-MM-DD.md',
    );
    expect(
      resolver.resolve(settings, date: date),
      'Journal/2026-10-16.md',
    );
  });

  test('expandMomentFormat supports M and D without zero pad', () {
    expect(
      resolver.expandMomentFormat('M/D/YYYY', DateTime(2026, 3, 5)),
      '3/5/2026',
    );
  });

  group('DailyNoteDate', () {
    test('formats and parses YYYY-MM-DD', () {
      expect(DailyNoteDate.formatIso(DateTime(2026, 10, 19)), '2026-10-19');
      expect(
        DailyNoteDate.tryParse('2026-10-19'),
        DateTime(2026, 10, 19),
      );
    });

    test('parses soft OCR-style dates', () {
      expect(
        DailyNoteDate.tryParse("19 Oct '26"),
        DateTime(2026, 10, 19),
      );
      expect(
        DailyNoteDate.tryParse('19 Oct 2026'),
        DateTime(2026, 10, 19),
      );
    });

    test('rejects invalid dates', () {
      expect(DailyNoteDate.tryParse(''), isNull);
      expect(DailyNoteDate.tryParse('Tasks'), isNull);
      expect(DailyNoteDate.tryParse('2026-13-01'), isNull);
    });
  });

  group('DailyNoteDate.tryParseLoose', () {
    final ref = DateTime(2026, 11, 27);

    test('keeps strict formats', () {
      expect(DailyNoteDate.tryParseLoose("19 Oct '26"), DateTime(2026, 10, 19));
      expect(DailyNoteDate.tryParseLoose('2026-11-20'), DateTime(2026, 11, 20));
    });

    test('handwritten hub variants', () {
      expect(
        DailyNoteDate.tryParseLoose("Fri 27 Nov '26"),
        DateTime(2026, 11, 27),
      );
      expect(
        DailyNoteDate.tryParseLoose('Friday, 27th November 2026'),
        DateTime(2026, 11, 27),
      );
      expect(
        DailyNoteDate.tryParseLoose('Nov 27, 2026'),
        DateTime(2026, 11, 27),
      );
      expect(DailyNoteDate.tryParseLoose('27/11/26'), DateTime(2026, 11, 27));
      expect(DailyNoteDate.tryParseLoose('27.11.2026'), DateTime(2026, 11, 27));
      expect(
        DailyNoteDate.tryParseLoose("Fri\n27 Nov '26"),
        DateTime(2026, 11, 27),
      );
      expect(
        DailyNoteDate.tryParseLoose('Fri 27 Nov', reference: ref),
        DateTime(2026, 11, 27),
      );
    });

    test('rejects names and tasks', () {
      expect(DailyNoteDate.tryParseLoose('Deshan'), isNull);
      expect(DailyNoteDate.tryParseLoose('Walk Sunday @ 07:30'), isNull);
      expect(DailyNoteDate.tryParseLoose('Book Car Service'), isNull);
      expect(DailyNoteDate.tryParseLoose('31/02/26'), isNull);
    });
  });
}
