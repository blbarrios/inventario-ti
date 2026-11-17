// Non-web fallback (used by tests and desktop): file pick/download are no-ops.
Future<String?> pickCsvFile() async => null;

void downloadCsv(String filename, String content) {}
