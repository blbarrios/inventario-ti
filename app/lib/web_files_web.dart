// dart:html is the lightest way to pick/download a file in this web app.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

/// Opens the browser's file chooser and returns the chosen file's text.
Future<String?> pickCsvFile() {
  final completer = Completer<String?>();
  final input = html.FileUploadInputElement()..accept = '.csv,text/csv';
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd
        .listen((_) => completer.complete(reader.result as String?));
    reader.onError.listen((_) => completer.complete(null));
    reader.readAsText(files.first);
  });
  input.click();
  return completer.future;
}

/// Triggers a browser download of [content] as [filename].
void downloadCsv(String filename, String content) {
  final blob = html.Blob([utf8.encode(content)], 'text/csv;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}
