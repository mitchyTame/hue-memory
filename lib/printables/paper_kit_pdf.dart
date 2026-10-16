import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../symbols/ink_library.dart';
import '../symbols/symbol_models.dart';
import '../theme/memory_hues.dart';
import 'hue_code.dart';

/// Memory-hues craft PDFs: A6 pack legend + hue-dot sticker sheet.
///
/// Glyphs are drawn with vector paths (Helvetica has no ZK unicode).
class PaperKitPdf {
  const PaperKitPdf();

  /// A6 portrait in PDF points (105 × 148 mm).
  static final PdfPageFormat a6 = PdfPageFormat(
    105 * PdfPageFormat.mm,
    148 * PdfPageFormat.mm,
  );

  static final PdfColor _paper = _pdf(MemoryHues.paper);
  static final PdfColor _ink = _pdf(MemoryHues.ink);
  static final PdfColor _muted = _pdf(MemoryHues.inkMuted);
  static final PdfColor _accent = _pdf(MemoryHues.accent);
  static final PdfColor _recall = _pdf(MemoryHues.recall);
  static final PdfColor _rule = _pdf(MemoryHues.rule);
  static final PdfColor _accentSoft = _pdf(MemoryHues.accentSoft);
  static final PdfColor _recallSoft = _pdf(MemoryHues.recallSoft);

  static PdfColor _pdf(Color c) => PdfColor(c.r, c.g, c.b, c.a);

  /// A6 legend for the active pack — glyph, id, folder / output hint.
  Future<Uint8List> buildLegend({
    required SymbolPack pack,
    String productName = 'hue-memory',
  }) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: a6,
        margin: const pw.EdgeInsets.all(18),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                productName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Ink legend - ${pack.displayName}',
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
              pw.SizedBox(height: 8),
              pw.Container(height: 1, color: _rule),
              pw.SizedBox(height: 10),
              ...pack.symbols.map(_legendRow),
              pw.Spacer(),
              pw.Text(
                'Circle a glyph in the corner meta zone. '
                'Vault paths are written by the app - never handwrite wiki brackets.',
                style: pw.TextStyle(fontSize: 7.5, color: _muted, height: 1.3),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _legendRow(PackSymbol s) {
    final dest = s.folder != null
        ? '${s.folder}/'
        : (s.section ?? s.output.name);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 28,
            height: 28,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: _accent, width: 1.2),
              color: _accentSoft,
            ),
            child: pw.CustomPaint(
              size: const PdfPoint(18, 18),
              painter: (canvas, size) =>
                  _paintGlyph(canvas, size, s.draw, _ink),
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  s.id,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.Text(
                  '${s.draw}  ->  $dest',
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sticker sheet: twin peel-dots per row (same 2-char code twice).
  Future<Uint8List> buildHueDotSheet({
    required List<String> codes,
    String productName = 'hue-memory',
  }) async {
    if (codes.isEmpty) {
      throw ArgumentError('codes must not be empty');
    }
    for (final c in codes) {
      if (!HueCode.isValid(c)) {
        throw ArgumentError('Invalid hue code: $c');
      }
    }

    final fills = [_accent, _ink, _recall];
    final softs = [_accentSoft, _paper, _recallSoft];

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: a6,
        margin: const pw.EdgeInsets.all(14),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                productName,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.Text(
                'Hue-dot twins - peel same code onto two pages',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
              pw.SizedBox(height: 6),
              pw.Container(height: 1, color: _rule),
              pw.SizedBox(height: 10),
              pw.Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < codes.length; i++)
                    _twinPair(
                      code: codes[i],
                      fill: fills[i % fills.length],
                      soft: softs[i % softs.length],
                    ),
                ],
              ),
              pw.Spacer(),
              pw.Text(
                'Pretty id for linking - vault still stores opaque page_id. '
                'Alphabet skips 0/O/1/l.',
                style: pw.TextStyle(fontSize: 7, color: _muted, height: 1.3),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _twinPair({
    required String code,
    required PdfColor fill,
    required PdfColor soft,
  }) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        _dot(code, fill, soft),
        pw.SizedBox(width: 6),
        _dot(code, fill, soft),
      ],
    );
  }

  pw.Widget _dot(String code, PdfColor fill, PdfColor soft) {
    return pw.Container(
      width: 36,
      height: 36,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: soft,
        border: pw.Border.all(color: fill, width: 1.4),
      ),
      child: pw.Text(
        code,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

void _paintGlyph(
  PdfGraphics canvas,
  PdfPoint size,
  String drawId,
  PdfColor ink,
) {
  final w = size.x;
  final h = size.y;
  final cx = w / 2;
  final cy = h / 2;
  canvas
    ..setStrokeColor(ink)
    ..setLineWidth(1.35)
    ..setLineCap(PdfLineCap.round)
    ..setLineJoin(PdfLineJoin.round);

  switch (drawId) {
    case InkDrawIds.circleOpen:
      canvas.drawEllipse(cx, cy, w * 0.32, h * 0.32);
      canvas.strokePath();
    case InkDrawIds.wave:
      final path = <PdfPoint>[
        PdfPoint(w * 0.12, cy),
        PdfPoint(w * 0.28, cy - h * 0.22),
        PdfPoint(w * 0.44, cy + h * 0.22),
        PdfPoint(w * 0.60, cy - h * 0.22),
        PdfPoint(w * 0.76, cy + h * 0.18),
        PdfPoint(w * 0.88, cy),
      ];
      canvas.moveTo(path.first.x, path.first.y);
      for (var i = 1; i < path.length; i++) {
        canvas.lineTo(path[i].x, path[i].y);
      }
      canvas.strokePath();
    case InkDrawIds.tripleBar:
      for (final t in [0.28, 0.5, 0.72]) {
        final y = h * t;
        canvas.drawLine(w * 0.18, y, w * 0.82, y);
      }
      canvas.strokePath();
    case InkDrawIds.diamond:
      canvas
        ..moveTo(cx, h * 0.12)
        ..lineTo(w * 0.82, cy)
        ..lineTo(cx, h * 0.88)
        ..lineTo(w * 0.18, cy)
        ..closePath()
        ..strokePath();
    case InkDrawIds.triangle:
      canvas
        ..moveTo(cx, h * 0.14)
        ..lineTo(w * 0.84, h * 0.82)
        ..lineTo(w * 0.16, h * 0.82)
        ..closePath()
        ..strokePath();
    case InkDrawIds.dot:
      canvas
        ..setFillColor(ink)
        ..drawEllipse(cx, cy, math.min(w, h) * 0.12, math.min(w, h) * 0.12)
        ..fillPath();
    default:
      canvas.drawEllipse(cx, cy, w * 0.2, h * 0.2);
      canvas.strokePath();
  }
}
