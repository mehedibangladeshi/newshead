import 'dart:io';

abstract class ArticleCache {
  Future<String?> read();
  Future<void> write(String contents);
  // When the cache was last written; null if never.
  Future<DateTime?> savedAt();
}

class FileArticleCache implements ArticleCache {
  final String path;

  FileArticleCache(this.path);

  @override
  Future<String?> read() async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String contents) async {
    final file = File(path);
    await file.writeAsString(contents);
  }

  @override
  Future<DateTime?> savedAt() async {
    final file = File(path);
    return await file.exists() ? file.lastModified() : null;
  }
}
