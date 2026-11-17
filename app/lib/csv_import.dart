import 'inventory_data.dart';

// Web picks/downloads via dart:html; elsewhere (tests) these are no-ops.
export 'web_files_stub.dart' if (dart.library.html) 'web_files_web.dart';

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
String assetsCsvTemplate() => 'codigo,nombre,tipo,icono,responsable,estado\r\n'
    'SW-R1-03,Switch de acceso,Switch,switch,Soporte TI,operational\r\n';

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
  final rows = _splitCsv(content)
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

  final assets = <CsvAsset>[];
  final errors = <CsvRowError>[];
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    String at(int i) => (i >= 0 && i < row.length) ? row[i].trim() : '';
    final code = at(ci), name = at(ni), type = at(ti);
    if (code.isEmpty || name.isEmpty || type.isEmpty) {
      errors.add(CsvRowError(r + 1, 'Código, nombre y tipo son obligatorios.'));
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

/// A small CSV reader that understands quoted fields and escaped quotes.
List<List<String>> _splitCsv(String input) {
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
    } else if (c == ',') {
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
