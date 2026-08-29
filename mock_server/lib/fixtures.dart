/// Mock 目录数据（歌曲 / 专辑 / 歌手 / 风格 / 歌单）。
///
/// 字段与 FNOS 音乐 API 返回结构对齐（简化版），供客户端模型解析测试。

library;

class MockAlbum {
  const MockAlbum(this.guid, this.name, this.coverId, this.year);
  final String guid;
  final String name;
  final String coverId;
  final int year;
}

class MockArtist {
  const MockArtist(this.guid, this.name, this.coverId);
  final String guid;
  final String name;
  final String coverId;
}

class MockGenre {
  const MockGenre(this.guid, this.name, this.coverId);
  final String guid;
  final String name;
  final String coverId;
}

class MockTrack {
  const MockTrack(
    this.guid,
    this.title,
    this.albumGuid,
    this.artistGuids,
    this.duration,
    this.format,
    this.codec,
    this.genreGuids,
    this.coverId,
    this.trackNo,
  );

  final String guid;
  final String title;
  final String albumGuid;
  final List<String> artistGuids;
  final int duration; // 毫秒（与真实 FNOS API / 客户端 SongEntity 契约一致）
  final String format; // flac / mp3 / wav ...
  final String codec; // flac / mp3 / pcm_s16le ...
  final List<String> genreGuids;
  final String coverId;
  final int trackNo;

  Map<String, Object?> toJson() {
    final MockAlbum album = albumByGuid[albumGuid]!;
    final List<Map<String, Object?>> artists = artistGuids
        .map((String g) {
          final MockArtist a = artistByGuid[g]!;
          return <String, Object?>{
            'guid': a.guid,
            'name': a.name,
            'coverId': a.coverId,
          };
        })
        .toList();
    final List<Map<String, Object?>> genres = genreGuids
        .map((String g) {
          final MockGenre genre = genreByGuid[g]!;
          return <String, Object?>{'guid': genre.guid, 'name': genre.name};
        })
        .toList();
    return <String, Object?>{
      'guid': guid,
      'title': title,
      'coverId': coverId,
      'year': album.year,
      'discNo': 1,
      'trackNo': trackNo,
      'duration': duration,
      'isCue': false,
      'album': <String, Object?>{
        'guid': album.guid,
        'name': album.name,
        'coverId': album.coverId,
        'year': album.year,
      },
      'artists': artists,
      'genres': genres,
      'isFavorite': false,
      'hasLyric': true,
      'audioSpec': <String, Object?>{
        'bitDepth': 16,
        'sampleRate': 44100,
        'channel': 2,
        'bitrate': 1411,
        'codec': codec,
        'format': format,
        'duration': duration,
        'size': duration ~/ 1000 * 44100 * 4,
        'path': '/music/示例库/$title.$format',
      },
    };
  }
}

final Map<String, MockAlbum> albumByGuid = <String, MockAlbum>{
  for (final MockAlbum a in albums) a.guid: a,
};

final Map<String, MockArtist> artistByGuid = <String, MockArtist>{
  for (final MockArtist a in artists) a.guid: a,
};

final Map<String, MockGenre> genreByGuid = <String, MockGenre>{
  for (final MockGenre g in genres) g.guid: g,
};

final List<MockAlbum> albums = <MockAlbum>[
  const MockAlbum('alb_001', '风起时', 'cov_001', 2023),
  const MockAlbum('alb_002', '山海', 'cov_002', 2022),
  const MockAlbum('alb_003', '星河入梦', 'cov_003', 2021),
  const MockAlbum('alb_004', '旧时光', 'cov_004', 2020),
  const MockAlbum('alb_005', '拾光', 'cov_005', 2019),
];

final List<MockArtist> artists = <MockArtist>[
  const MockArtist('art_001', '林晚风', 'cov_101'),
  const MockArtist('art_002', '许清扬', 'cov_102'),
  const MockArtist('art_003', '苏黎', 'cov_103'),
  const MockArtist('art_004', '顾北辰', 'cov_104'),
  const MockArtist('art_005', '顾北寒', 'cov_105'),
  const MockArtist('art_006', '南栀', 'cov_106'),
];

final List<MockGenre> genres = <MockGenre>[
  const MockGenre('gen_001', '流行', 'cov_g1'),
  const MockGenre('gen_002', '民谣', 'cov_g2'),
  const MockGenre('gen_003', '古典', 'cov_g3'),
];

final List<MockTrack> tracks = <MockTrack>[
  const MockTrack('trk_001', '风起时', 'alb_001', ['art_001', 'art_002'], 214000, 'flac', 'flac', ['gen_001'], 'cov_001', 1),
  const MockTrack('trk_002', '初见', 'alb_001', ['art_001'], 197000, 'flac', 'flac', ['gen_001'], 'cov_001', 2),
  const MockTrack('trk_003', '山海', 'alb_002', ['art_002'], 243000, 'mp3', 'mp3', ['gen_002'], 'cov_002', 1),
  const MockTrack('trk_004', '星河入梦', 'alb_003', ['art_003'], 268000, 'flac', 'flac', ['gen_003'], 'cov_003', 1),
  const MockTrack('trk_005', '月光', 'alb_003', ['art_003', 'art_004'], 221000, 'mp3', 'mp3', ['gen_001', 'gen_003'], 'cov_003', 2),
  const MockTrack('trk_006', '旧时光', 'alb_004', ['art_004'], 186000, 'mp3', 'mp3', ['gen_002'], 'cov_004', 1),
  const MockTrack('trk_007', '老街', 'alb_004', ['art_005'], 204000, 'mp3', 'mp3', ['gen_002'], 'cov_004', 2),
  const MockTrack('trk_008', '拾光', 'alb_005', ['art_006'], 232000, 'wav', 'pcm_s16le', ['gen_001'], 'cov_005', 1),
  const MockTrack('trk_009', '晚风', 'alb_005', ['art_006', 'art_001'], 209000, 'flac', 'flac', ['gen_001', 'gen_002'], 'cov_005', 2),
  const MockTrack('trk_010', '远山', 'alb_002', ['art_002'], 256000, 'flac', 'flac', ['gen_002'], 'cov_002', 2),
  const MockTrack('trk_011', '海风', 'alb_002', ['art_001'], 198000, 'mp3', 'mp3', ['gen_001'], 'cov_002', 3),
  const MockTrack('trk_012', '夜航', 'alb_003', ['art_004'], 274000, 'flac', 'flac', ['gen_003'], 'cov_003', 3),
  // 纯 ASCII 标题，方便 adb shell input text 输入搜索关键词验证。
  const MockTrack('trk_013', 'Demo Song', 'alb_003', ['art_005'], 180000, 'flac', 'flac', ['gen_001'], 'cov_003', 4),
];

final Map<String, MockTrack> trackByGuid = <String, MockTrack>{
  for (final MockTrack t in tracks) t.guid: t,
};

/// 歌词（LRC）fixtures：内联翻译 + offset 元数据。
final Map<String, String> lyricsByTrack = <String, String>{
  'trk_001': '''[ti:风起时]
[ar:林晚风 / 许清扬]
[offset:0]
[00:00.00]风起的时候 (When the wind rises)
[00:03.50]我听见你的声音 (I hear your voice)
[00:07.20]穿过整片森林 (Through the forest)
[00:10.80]来到我身边 (Coming to me)
[00:14.40]啦～啦～啦～
[00:18.00]啦～啦～啦～
''',
  'trk_003': '''[ti:山海]
[ar:许清扬]
[00:00.00]山海皆可平
[00:04.20]难平是人心
[00:08.60]走过万水千山
[00:12.90]只为遇见你
''',
  'trk_006': '''[ti:旧时光]
[ar:顾北辰]
[00:00.00]旧时光它慢慢走
[00:05.10]带走年少不知愁
[00:10.30]留下泛黄的回忆
[00:15.20]在梦里来回游走
''',
};
