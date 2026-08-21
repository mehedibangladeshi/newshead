import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newshead/data/article_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('article_cache_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('read returns null when the cache file does not exist', () async {
    final cache = FileArticleCache(p.join(tempDir.path, 'missing.json'));
    expect(await cache.read(), isNull);
  });

  test('write then read round-trips the same content', () async {
    final cache = FileArticleCache(p.join(tempDir.path, 'cache.json'));
    await cache.write('{"hello":"world"}');
    expect(await cache.read(), '{"hello":"world"}');
  });

  test('write overwrites previous content', () async {
    final cache = FileArticleCache(p.join(tempDir.path, 'cache.json'));
    await cache.write('first');
    await cache.write('second');
    expect(await cache.read(), 'second');
  });
}
