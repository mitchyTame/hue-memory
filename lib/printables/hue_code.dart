import 'dart:math';

/// Pretty 2-character hue-dot codes (no `0/O/1/l` confusion).
///
/// Humans see these on stickers / confirm UI; vault keeps opaque `page_id`.
class HueCode {
  HueCode({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Same friendly alphabet as [PageId] short stems.
  static const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';

  /// Generate one 2-char code, e.g. `ka`, `mo`, `ri`.
  String next() {
    final a = alphabet[_random.nextInt(alphabet.length)];
    final b = alphabet[_random.nextInt(alphabet.length)];
    return '$a$b';
  }

  /// [count] unique codes (retries on collision within the batch).
  List<String> batch(int count) {
    if (count <= 0) return const [];
    final out = <String>{};
    var guard = 0;
    while (out.length < count && guard < count * 40) {
      out.add(next());
      guard++;
    }
    if (out.length < count) {
      throw StateError('Could not mint $count unique hue codes');
    }
    return out.toList();
  }

  /// Soft validation for OCR / power-user hand codes (alphabet only).
  static bool isValid(String code) {
    if (code.length != 2) return false;
    return alphabet.contains(code[0]) && alphabet.contains(code[1]);
  }
}
