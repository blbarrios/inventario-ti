import 'dart:convert';

import 'inventory_data.dart';
// Web picks/downloads via dart:html; elsewhere (tests) these are no-ops.
import 'web_files_stub.dart' if (dart.library.html) 'web_files_web.dart'
    as files;

export 'web_files_stub.dart' if (dart.library.html) 'web_files_web.dart'
    show downloadCsv;

/// One parsed, validated row ready to create as an asset.
class CsvAsset {
  CsvAsset({
    required this.code,
    required this.name,
    required this.type,
    required this.icon,
    required this.responsible,
    required this.status,
  });
  final String code;
  final String name;
  final String type;
  final DeviceIcon icon;
  final String responsible;
  final AssetStatus status;
}

class CsvRowError {
  CsvRowError(this.line, this.message);
  final int line;
  final String message;
}

class CsvParseResult {
  CsvParseResult(this.assets, this.errors);
  final List<CsvAsset> assets;
  final List<CsvRowError> errors;
}

/// The downloadable template, with one example row.
// Uses `;` because that is what Excel in Spanish expects (imports accept `;`,
// `,` or tab).
String assetsCsvTemplate() => 'codigo;nombre;tipo;icono;responsable;estado\r\n'
    'SW-R1-03;Switch de acceso;Switch;switch;Soporte TI;operational\r\n';

String _norm(String value) {
  var v = value.trim().toLowerCase();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n'};
  accents.forEach((k, r) => v = v.replaceAll(k, r));
  return v;
}

DeviceIcon? _iconFromText(String value) {
  final v = _norm(value);
  for (final icon in DeviceIcon.values) {
    if (icon.key.toLowerCase() == v || _norm(icon.label) == v) return icon;
  }
  return null;
}

AssetStatus? _statusFromText(String value) {
  final v = _norm(value);
  for (final status in AssetStatus.values) {
    if (status.name == v || _norm(status.label) == v) return status;
  }
  return null;
}

/// Parse a CSV string into asset rows. Header is case/accent-insensitive;
/// `codigo`, `nombre` and `tipo` are required; `icono`, `responsable` and
/// `estado` are optional.
CsvParseResult parseAssetsCsv(String content) {
  // Excel adds a BOM to UTF-8 files; drop it so the first header matches.
  if (content.startsWith('﻿')) content = content.substring(1);
  final rows = _splitCsv(content, _detectDelimiter(content))
      .where((row) => row.any((cell) => cell.trim().isNotEmpty))
      .toList();
  if (rows.isEmpty) {
    return CsvParseResult([], [CsvRowError(0, 'El archivo está vacío.')]);
  }
  final header = rows.first.map(_norm).toList();
  int col(List<String> names) => header.indexWhere((h) => names.contains(h));
  final ci = col(['codigo', 'code']);
  final ni = col(['nombre', 'name']);
  final ti = col(['tipo', 'type']);
  final ii = col(['icono', 'icon']);
  final ri = col(['responsable', 'responsible']);
  final si = col(['estado', 'status']);

  if (ci < 0 || ni < 0 || ti < 0) {
    return CsvParseResult([], [
      CsvRowError(1,
          'Faltan columnas obligatorias. Se requieren: codigo, nombre, tipo.')
    ]);
  }

  String cell(List<String> row, int i) =>
      (i >= 0 && i < row.length) ? row[i].trim() : '';

  // A code used on more than one row is ambiguous: reject every such row so
  // nothing half-right gets in (common when a missing serial is typed as 0).
  final codeCount = <String, int>{};
  for (final row in rows.skip(1)) {
    final code = cell(row, ci).toLowerCase();
    if (code.isNotEmpty) codeCount[code] = (codeCount[code] ?? 0) + 1;
  }

  final assets = <CsvAsset>[];
  final errors = <CsvRowError>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    String at(int i) => cell(row, i);
    final code = at(ci), name = at(ni), type = at(ti);
    if (code.isEmpty || name.isEmpty || type.isEmpty) {
      errors.add(CsvRowError(r + 1, 'Código, nombre y tipo son obligatorios.'));
      continue;
    }
    final repeats = codeCount[code.toLowerCase()] ?? 0;
    if (repeats > 1) {
      errors.add(CsvRowError(r + 1,
          '$name: el código «$code» se repite en $repeats filas. Usa un código único (p. ej. el serial).'));
      continue;
    }
    final iconText = at(ii);
    final statusText = at(si);
    assets.add(CsvAsset(
      code: code,
      name: name,
      type: type,
      icon: iconText.isEmpty
          ? deviceIconForType(type)
          : (_iconFromText(iconText) ?? deviceIconForType(type)),
      responsible: at(ri),
      status: statusText.isEmpty
          ? AssetStatus.unknown
          : (_statusFromText(statusText) ?? AssetStatus.unknown),
    ));
  }
  return CsvParseResult(assets, errors);
}

/// Excel in Spanish saves with `;`; others use `,` or tab. Pick whichever
/// appears most in the header line (outside quotes).
String _detectDelimiter(String content) {
  final header = content
      .split(RegExp(r'\r?\n|\r'))
      .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
  final counts = {',': 0, ';': 0, '\t': 0};
  var inQuotes = false;
  for (final c in header.split('')) {
    if (c == '"') inQuotes = !inQuotes;
    if (!inQuotes && counts.containsKey(c)) counts[c] = counts[c]! + 1;
  }
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

/// Turn file bytes into text: UTF-8 when valid, else Windows-1252/Latin-1
/// (what Excel on Windows usually saves as "CSV").
String decodeCsvBytes(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

/// Opens the file chooser and returns the chosen CSV as text.
Future<String?> pickCsvFile() async {
  final bytes = await files.pickCsvBytes();
  return bytes == null ? null : decodeCsvBytes(bytes);
}

/// A small CSV reader that understands quoted fields and escaped quotes.
List<List<String>> _splitCsv(String input, String delimiter) {
  final normalized = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < normalized.length; i++) {
    final c = normalized[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < normalized.length && normalized[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == delimiter) {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n') {
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field = StringBuffer();
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
