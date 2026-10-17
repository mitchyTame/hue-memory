import 'package:flutter/foundation.dart';

/// Normalized 0–1 rect over the viewfinder for the paper ink glyph.
///
/// Drag/resize on camera; persisted for the capture session only.
@immutable
class SymbolBoxRect {
  const SymbolBoxRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  /// Default top-left meta-zone habit from the paper kit brief.
  static const SymbolBoxRect defaultMeta = SymbolBoxRect(
    left: 0.04,
    top: 0.04,
    width: 0.22,
    height: 0.12,
  );

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;

  SymbolBoxRect copyWith({
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return SymbolBoxRect(
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  /// Clamp into the viewfinder with a usable minimum size.
  SymbolBoxRect clamped({
    double minSize = 0.08,
    double maxSize = 0.55,
  }) {
    var w = width.clamp(minSize, maxSize);
    var h = height.clamp(minSize, maxSize);
    var l = left.clamp(0.0, 1.0 - w);
    var t = top.clamp(0.0, 1.0 - h);
    return SymbolBoxRect(left: l, top: t, width: w, height: h);
  }

  Map<String, double> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  factory SymbolBoxRect.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaultMeta;
    return SymbolBoxRect(
      left: (json['left'] as num?)?.toDouble() ?? defaultMeta.left,
      top: (json['top'] as num?)?.toDouble() ?? defaultMeta.top,
      width: (json['width'] as num?)?.toDouble() ?? defaultMeta.width,
      height: (json['height'] as num?)?.toDouble() ?? defaultMeta.height,
    ).clamped();
  }
}

/// In-memory session for camera symbol chip + movable box.
class CaptureSessionPrefs {
  CaptureSessionPrefs({
    this.symbolId = '',
    this.symbolBox = SymbolBoxRect.defaultMeta,
  });

  String symbolId;
  SymbolBoxRect symbolBox;
}
