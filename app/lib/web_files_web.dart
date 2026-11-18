// dart:html is the lightest way to pick/download a file in this web app.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

/// Opens the browser's file chooser and returns the chosen file's raw bytes,
/// so the caller can decode UTF-8 or Excel's Windows-1252 correctly.
Future<List<int>?> pickCsvBytes() {
  final completer = Completer<List<int>?>();
  final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      completer.complete(result is ByteBuffer
          ? result.asUint8List()
          : result is Uint8List
              ? result
              : null);
    });
    reader.onError.listen((_) => completer.complete(null));
    reader.readAsArrayBuffer(files.first);
  });
  input.click();
  return completer.future;
}

/// Triggers a browser download of [content] as [filename]. A UTF-8 BOM makes
/// Excel show accents correctly when it opens the file.
void downloadCsv(String filename, String content) {
  final blob = html.Blob([
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)])
  ], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}
