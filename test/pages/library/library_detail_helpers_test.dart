import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/state/song_state.dart';
import 'package:fnmusic/pages/library/library_detail_pages.dart';

SongEntity _song(String title, {int? trackNo, int? discNo, int? durationMs}) {
  return SongEntity(
    guid: 'g-$title',
    title: title,
    artistDisplay: '歌手$title',
    trackNo: trackNo,
    discNo: discNo,
    durationMs: durationMs,
  );
}

void main() {
  group('primaryArtistLabel', () {
    test('null / 空串 → 未知歌手', () {
      expect(primaryArtistLabel(null), '未知歌手');
      expect(primaryArtistLabel('  '), '未知歌手');
    });

    test('单歌手原样', () {
      expect(primaryArtistLabel('陈琳'), '陈琳');
    });

    test('多歌手 → 主歌手 + 等', () {
      expect(primaryArtistLabel('陈琳 / 周深'), '陈琳 等');
      expect(primaryArtistLabel('A、B'), 'A 等');
    });
  });

  group('sortAlbumDetailSongs', () {
    test('轨道号升序：碟号优先再按轨道号', () {
      final List<SongEntity> songs = <SongEntity>[
        _song('曲2', discNo: 1, trackNo: 2),
        _song('曲1', discNo: 1, trackNo: 1),
        _song('曲B', discNo: 2, trackNo: 1),
      ];
      final List<SongEntity> sorted = sortAlbumDetailSongs(
        songs,
        sortKey: 'trackNumber',
        ascending: true,
      );
      expect(sorted.map((SongEntity s) => s.title).toList(),
          <String>['曲1', '曲2', '曲B']);
    });

    test('轨道号降序', () {
      final List<SongEntity> sorted = sortAlbumDetailSongs(
        <SongEntity>[
          _song('曲2', trackNo: 2),
          _song('曲1', trackNo: 1),
        ],
        sortKey: 'trackNumber',
        ascending: false,
      );
      expect(sorted.first.title, '曲2');
    });

    test('歌曲名称按自然排序（数字按数值，中文转拼音）', () {
      // 拼音：曲→qu；'曲2' 分词为 ['qu',2]，'曲B' 为 ['qub']；前缀 'qu' < 'qub'。
      final List<SongEntity> sorted = sortAlbumDetailSongs(
        <SongEntity>[_song('曲B'), _song('曲2'), _song('曲10'), _song('曲1')],
        sortKey: 'title',
        ascending: true,
      );
      expect(sorted.map((SongEntity s) => s.title).toList(),
          <String>['曲1', '曲2', '曲10', '曲B']);
    });

    test('歌曲时长降序', () {
      final List<SongEntity> sorted = sortAlbumDetailSongs(
        <SongEntity>[
          _song('短', durationMs: 100000),
          _song('长', durationMs: 300000),
        ],
        sortKey: 'duration',
        ascending: false,
      );
      expect(sorted.first.title, '长');
    });
  });
}
