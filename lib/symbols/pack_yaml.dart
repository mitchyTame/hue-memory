import 'package:yaml/yaml.dart';

import 'symbol_models.dart';

/// Parse a pack YAML document (asset or vault `active.yaml`) into [SymbolPack].
class PackYaml {
  const PackYaml();

  SymbolPack parse(String yamlSource) {
    final doc = loadYaml(yamlSource);
    if (doc is! YamlMap) {
      throw FormatException('Pack YAML root must be a map');
    }
    final id = doc['id']?.toString();
    if (id == null || id.isEmpty) {
      throw FormatException('Pack YAML missing id');
    }
    final libraryRef = doc['library_ref']?.toString() ?? 'ink-v1';
    final label = doc['label']?.toString();
    final rawSymbols = doc['symbols'];
    if (rawSymbols is! YamlList) {
      throw FormatException('Pack YAML missing symbols list');
    }

    final symbols = <PackSymbol>[];
    for (final item in rawSymbols) {
      if (item is! YamlMap) {
        throw FormatException('Each symbol must be a map');
      }
      symbols.add(_parseSymbol(item));
    }
    if (symbols.isEmpty) {
      throw FormatException('Pack YAML has no symbols');
    }
    if (symbols.every((s) => s.id != 'inbox')) {
      throw FormatException('Pack must include an inbox symbol');
    }

    return SymbolPack(
      id: id,
      libraryRef: libraryRef,
      label: label,
      symbols: symbols,
    );
  }

  /// Serialize a list of extra (user-added) symbols — no pack wrapper.
  String encodeExtras(List<PackSymbol> extras) {
    if (extras.isEmpty) return 'extras: []\n';
    final buffer = StringBuffer()..writeln('extras:');
    for (final s in extras) {
      buffer
        ..writeln('  - id: ${s.id}')
        ..writeln('    draw: ${s.draw}')
        ..writeln('    glyphs: [${s.glyphs.map(_yamlString).join(', ')}]');
      if (s.folder != null) {
        buffer.writeln('    folder: ${s.folder}');
      }
      buffer.writeln('    output: ${_outputToYaml(s.output)}');
      if (s.section != null) {
        buffer.writeln('    section: ${_yamlString(s.section!)}');
      }
      if (s.reviewGate != null) {
        buffer.writeln('    review_gate: ${s.reviewGate}');
      }
    }
    return buffer.toString();
  }

  /// Parse [encodeExtras] output (or empty → `[]`).
  List<PackSymbol> parseExtras(String yamlSource) {
    final trimmed = yamlSource.trim();
    if (trimmed.isEmpty) return const [];
    final doc = loadYaml(trimmed);
    if (doc is! YamlMap) {
      throw FormatException('Extras YAML root must be a map');
    }
    final raw = doc['extras'];
    if (raw == null) return const [];
    if (raw is! YamlList) {
      throw FormatException('extras must be a list');
    }
    final out = <PackSymbol>[];
    for (final item in raw) {
      if (item is! YamlMap) {
        throw FormatException('Each extra must be a map');
      }
      out.add(_parseSymbol(item));
    }
    return out;
  }

  /// Serialize a pack to YAML text (prefs mirror — never the vault).
  String encode(SymbolPack pack) {
    final buffer = StringBuffer()
      ..writeln('id: ${pack.id}')
      ..writeln('library_ref: ${pack.libraryRef}');
    if (pack.label != null && pack.label!.isNotEmpty) {
      buffer.writeln('label: ${pack.label}');
    }
    buffer.writeln('symbols:');
    for (final s in pack.symbols) {
      buffer
        ..writeln('  - id: ${s.id}')
        ..writeln('    draw: ${s.draw}')
        ..writeln('    glyphs: [${s.glyphs.map(_yamlString).join(', ')}]');
      if (s.folder != null) {
        buffer.writeln('    folder: ${s.folder}');
      }
      buffer.writeln('    output: ${_outputToYaml(s.output)}');
      if (s.section != null) {
        buffer.writeln('    section: ${_yamlString(s.section!)}');
      }
      if (s.reviewGate != null) {
        buffer.writeln('    review_gate: ${s.reviewGate}');
      }
    }
    return buffer.toString();
  }

  PackSymbol _parseSymbol(YamlMap map) {
    final id = map['id']?.toString();
    final draw = map['draw']?.toString();
    if (id == null || draw == null) {
      throw FormatException('Symbol requires id and draw');
    }
    final glyphsRaw = map['glyphs'];
    final glyphs = <String>[];
    if (glyphsRaw is YamlList) {
      for (final g in glyphsRaw) {
        glyphs.add(g.toString());
      }
    }
    if (glyphs.isEmpty) {
      throw FormatException('Symbol $id needs glyphs');
    }

    return PackSymbol(
      id: id,
      draw: draw,
      glyphs: glyphs,
      folder: map['folder']?.toString(),
      output: _outputFromYaml(map['output']?.toString() ?? 'markdown'),
      section: map['section']?.toString(),
      reviewGate: map['review_gate']?.toString(),
    );
  }

  static SymbolOutput _outputFromYaml(String value) {
    switch (value) {
      case 'canvas':
        return SymbolOutput.canvas;
      case 'inbox':
        return SymbolOutput.inbox;
      case 'daily-note-append':
        return SymbolOutput.dailyNoteAppend;
      case 'markdown':
      default:
        return SymbolOutput.markdown;
    }
  }

  static String _outputToYaml(SymbolOutput output) {
    switch (output) {
      case SymbolOutput.canvas:
        return 'canvas';
      case SymbolOutput.inbox:
        return 'inbox';
      case SymbolOutput.dailyNoteAppend:
        return 'daily-note-append';
      case SymbolOutput.markdown:
        return 'markdown';
    }
  }

  static String _yamlString(String value) {
    final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return '"$escaped"';
  }
}
