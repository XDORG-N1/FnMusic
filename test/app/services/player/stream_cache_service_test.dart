import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';

void main() {
  group('StreamCacheService.selectEvictions', () {
    CacheEntry entry(int bytes, int lastAccessed) =>
        CacheEntry(sizeBytes: bytes, lastAccessedMs: lastAccessed);

    test('未超限不淘汰', () {
      final entries = <String, CacheEntry>{
        'a': entry(10, 1),
        'b': entry(10, 2),
        'c': entry(10, 3),
      };
      expect(StreamCacheService.selectEvictions(entries: entries, maxBytes: 100),
          isEmpty);
    });

    test('超过上限按最久未用淘汰', () {
      final entries = <String, CacheEntry>{
        'a': entry(100, 1), // 最旧
        'b': entry(100, 2),
        'c': entry(100, 3),
      };
      // 上限 150 → 需腾出 ≥150。
      final evict = StreamCacheService.selectEvictions(
          entries: entries, maxBytes: 150);
      expect(evict, contains('a')); // 最旧的先被淘汰
      expect(evict.length, lessThanOrEqualTo(2)); // 保留至少一条
    });

    test('单条超大文件也保留（不空目录）', () {
      final entries = <String, CacheEntry>{
        'huge': entry(999, 1),
      };
      expect(StreamCacheService.selectEvictions(entries: entries, maxBytes: 10),
          isEmpty);
    });

    test('空集合返回空', () {
      expect(
          StreamCacheService.selectEvictions(
              entries: const <String, CacheEntry>{}, maxBytes: 10),
          isEmpty);
    });

    test('刚好等于上限不淘汰', () {
      final entries = <String, CacheEntry>{
        'a': entry(10, 1),
        'b': entry(10, 2),
      };
      expect(
          StreamCacheService.selectEvictions(entries: entries, maxBytes: 20),
          isEmpty);
    });
  });
}
