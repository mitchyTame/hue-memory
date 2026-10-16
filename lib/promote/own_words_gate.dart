/// Own-words gate for ∼ fleeting → ◇ permanent (promote ritual).
abstract final class OwnWordsGate {
  /// Returns an error message when the rewrite is not allowed; null if ok.
  ///
  /// [keepOcrShallow] opts out of rewrite but tags the permanent as shallow.
  static String? validate({
    required String ownWords,
    required String sourceBody,
    bool keepOcrShallow = false,
  }) {
    final words = ownWords.trim();
    if (keepOcrShallow) {
      return null;
    }
    if (words.isEmpty) {
      return 'Write the idea in your own words';
    }
    if (words.length < 8) {
      return 'A bit short — give the idea a full sentence';
    }
    if (_norm(words) == _norm(sourceBody)) {
      return 'Rewrite in your own words (or mark Keep OCR)';
    }
    return null;
  }

  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
