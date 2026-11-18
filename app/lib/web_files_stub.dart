// Non-web fallback (used by tests and desktop): file pick/download are no-ops.
Future<List<int>?> pickCsvBytes() async => null;

void downloadCsv(String filename, String content) {}
