import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/services/feiniu/api_models.dart';

/// `listItemsOf` 兼容解析：裸数组 与 分页 `{list, total}` 两种响应形态。
///
/// 回归背景：专辑 / 歌手 / 风格 / 歌单「详情曲目」接口在真实 FNOS 上返回
/// 分页包裹 `{list, total}`，旧实现按裸 `List` 强转每次点击都抛 TypeError。
void main() {
  group('listItemsOf', () {
    test('裸数组原样返回', () {
      final List<Object?> items = <Object?>[
        <String, Object?>{'guid': 'a'},
        <String, Object?>{'guid': 'b'},
      ];
      expect(listItemsOf(items), same(items));
    });

    test('分页 `{list, total}` 取出 list', () {
      final Object data = <String, Object?>{
        'list': <Object?>[<String, Object?>{'guid': 'a'}],
        'total': 1,
      };
      expect(listItemsOf(data), hasLength(1));
    });

    test('分页 `{list, total}` 中 list 为空数组仍返回空列表', () {
      final Object data = <String, Object?>{'list': <Object?>[], 'total': 0};
      expect(listItemsOf(data), isEmpty);
    });

    test('Map 但缺 list 字段 → 空列表', () {
      final Object data = <String, Object?>{'total': 0};
      expect(listItemsOf(data), isEmpty);
    });

    test('null / 字符串 / 数字 → 空列表', () {
      expect(listItemsOf(null), isEmpty);
      expect(listItemsOf('nope'), isEmpty);
      expect(listItemsOf(42), isEmpty);
    });
  });
}
