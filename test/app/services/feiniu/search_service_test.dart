import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/search_service.dart';

/// 验证搜索接口的**分页响应**解析：真实 FNOS `/search/track` 等返回
/// `data: {list, total}`（与其它 `/xxx/list` 一致），而非裸数组。
/// 旧实现把 `data` 强转 `List`，每次搜索都抛 TypeError。
void main() {
  group('FnSearchService 分页解析', () {
    test('歌曲：分页响应 `{list, total}` 解析出曲目列表', () {
      final Object data = <String, Object?>{
        'list': <Object?>[
          <String, Object?>{
            'guid': 'b4595419cd2e4305884ca8d337d346ec',
            'title': '花样年华',
            'coverId': 'album_9c316ca067db4a618541b13373998988',
            'year': null,
            'discNo': 1,
            'trackNo': 4,
            'duration': 312680,
            'isCue': true,
            'album': <String, Object?>{
              'guid': 'album_9c316ca067db4a618541b13373998988',
              'name': '花样年华',
            },
            'artists': <Object?>[
              <String, Object?>{'guid': 'a1', 'name': '周某某'},
            ],
          },
        ],
        'total': 1,
      };

      final ApiPage<FnTrack> page = FnSearchService.parseTracksPage(data);
      expect(page.total, 1);
      expect(page.list, hasLength(1));
      expect(page.list.single.guid, 'b4595419cd2e4305884ca8d337d346ec');
      expect(page.list.single.title, '花样年华');
      expect(page.list.single.album?.name, '花样年华');
      expect(page.list.single.artists.single.name, '周某某');
    });

    test('专辑：分页响应解析出专辑列表', () {
      final Object data = <String, Object?>{
        'list': <Object?>[
          <String, Object?>{
            'guid': 'album_x',
            'name': '测试专辑',
            'coverId': 'album_cover_x',
            'year': 2024,
          },
        ],
        'total': 1,
      };

      final ApiPage<FnAlbum> page = FnSearchService.parseAlbumsPage(data);
      expect(page.list, hasLength(1));
      expect(page.list.single.name, '测试专辑');
      expect(page.list.single.year, 2024);
    });

    test('歌手：分页响应解析出歌手列表', () {
      final Object data = <String, Object?>{
        'list': <Object?>[
          <String, Object?>{'guid': 'artist_x', 'name': '测试歌手'},
        ],
        'total': 1,
      };

      final ApiPage<FnArtist> page = FnSearchService.parseArtistsPage(data);
      expect(page.list.single.name, '测试歌手');
    });

    test('回归：旧实现按裸数组解析（TypeError），现在按空结果处理不崩溃', () {
      // 旧代码 `data as List` 遇到 Map 会抛 _TypeError；现在非 Map 一律按空处理。
      final Object data = <String, Object?>{'list': <Object?>[], 'total': 0};
      final ApiPage<FnTrack> page = FnSearchService.parseTracksPage(data);
      expect(page.list, isEmpty);
      expect(page.total, 0);
    });

    test('空结果：`{list: [], total: 0}` 正常返回空页', () {
      final ApiPage<FnTrack> page =
          FnSearchService.parseTracksPage(<String, Object?>{
        'list': <Object?>[],
        'total': 0,
      });
      expect(page.list, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });
}
