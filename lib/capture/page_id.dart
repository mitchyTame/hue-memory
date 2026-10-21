import 'dart:math';

/// Opaque short page ids: `YYYYMMDD` + `-` + 4 alphanumerics (e.g. `20261016-p7k2`).
class PageId {
  PageId({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Friendly alphabet — avoids `0/O/1/l` confusion (same spirit as hue-dot codes).
  static const _alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

  String generate({DateTime? at}) {
    final when = at ?? DateTime.now();
    final date =
        '${when.year.toString().padLeft(4, '0')}'
        '${when.month.toString().padLeft(2, '0')}'
        '${when.day.toString().padLeft(2, '0')}';
    final suffix = List.generate(
      4,
      (_) => _alphabet[_random.nextInt(_alphabet.length)],
    ).join();
    return '$date-$suffix';
  }

  /// Short stem after the date (`p7k2` from `20261016-p7k2`).
  static String shortStem(String pageId) {
    final dash = pageId.lastIndexOf('-');
    if (dash == -1 || dash == pageId.length - 1) return pageId;
    return pageId.substring(dash + 1);
  }
}
