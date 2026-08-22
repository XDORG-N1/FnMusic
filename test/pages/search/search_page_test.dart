import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/search_service.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';
import 'package:fnmusic/pages/search/search_page.dart';

import '../../helpers/fake_engine.dart';

FnTrack _track(int i, {String? title}) {
  return FnTrack.fromJson(<String, Object?>{
    'guid': 'track-$i',
    'title': title ?? '歌曲$i',
    'duration': 210000,
    'artists': <Object?>[
      <String, Object?>{'guid': 'artist-$i', 'name': '歌手$i'},
    ],
    'album': <String, Object?>{'guid': 'album-$i', 'name': '专辑$i'},
  });
}

FnAlbum _album(int i, {String? name}) {
  return FnAlbum.fromJson(<String, Object?>{
    'guid': 'album-$i',
    'name': name ?? '专辑$i',
    'year': 2024,
  });
}

FnArtist _artist(int i, {String? name}) {
  return FnArtist.fromJson(<String, Object?>{
    'guid': 'artist-$i',
    'name': name ?? '歌手$i',
  });
}

ApiPage<T> _page<T>(List<T> list, {int total = 0}) {
  return ApiPage<T>(
    list: list,
    total: total > 0 ? total : list.length,
    page: 1,
    pageSize: 50,
  );
}

/// 注入三路搜索 override（歌曲/专辑/歌手），并记录调用参数。
void _installOverrides() {
  FnSearchService.searchTracksOverride =
      (String keyword, int page, int size) async => _page<FnTrack>(<FnTrack>[
            _track(1, title: '花样年华'),
            _track(2, title: '夜曲'),
          ]);
  FnSearchService.searchAlbumsOverride =
      (String keyword, int page, int size) async => _page<FnAlbum>(<FnAlbum>[
            _album(1, name: '花样年华 专辑'),
          ]);
  FnSearchService.searchArtistsOverride =
      (String keyword, int page, int size) async => _page<FnArtist>(<FnArtist>[
            _artist(1, name: '周某某'),
          ]);
}

Future<void> _submitSearch(WidgetTester tester, String keyword) async {
  await tester.enterText(find.byType(TextField), keyword);
  await tester.pump();
  // 点 AppBar 搜索按钮触发搜索（等价于软键盘搜索键）。
  await tester.tap(find.byIcon(Icons.search));
  await tester.pumpAndSettle();
}

void main() {
  late FakeEngine fakeMain;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.instance.setServerUrl('http://test');
    StreamCacheService.instance.enabled = false;
    fakeMain = FakeEngine();
    setupPlayerForTest(fakeMain);
    FnSearchService.searchTracksOverride = null;
    FnSearchService.searchAlbumsOverride = null;
    FnSearchService.searchArtistsOverride = null;
  });

  tearDown(() {
    FnSearchService.searchTracksOverride = null;
    FnSearchService.searchAlbumsOverride = null;
    FnSearchService.searchArtistsOverride = null;
  });

  testWidgets('提交关键词后渲染歌曲/专辑/歌手结果', (WidgetTester tester) async {
    _installOverrides();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    expect(find.text('输入关键词开始搜索'), findsOneWidget);

    await _submitSearch(tester, '花样');

    // 三个分区都渲染。
    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('花样年华'), findsOneWidget);
    expect(find.text('夜曲'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('花样年华 专辑'), findsOneWidget);
    expect(find.text('歌手'), findsOneWidget);
    expect(find.text('周某某'), findsOneWidget);
  });

  testWidgets('点按歌曲结果整表入队并播放', (WidgetTester tester) async {
    _installOverrides();

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await _submitSearch(tester, '花样');

    await tester.tap(find.text('夜曲'));
    await tester.pumpAndSettle();

    // FakeEngine.play 被调用（点按即播）。
    expect(fakeMain.playCalls, greaterThan(0));
  });

  testWidgets('搜索失败显示错误并支持重试', (WidgetTester tester) async {
    int calls = 0;
    FnSearchService.searchTracksOverride =
        (String keyword, int page, int size) async {
      calls++;
      if (calls == 1) throw Exception('网络错误');
      return _page<FnTrack>(<FnTrack>[_track(1)]);
    };
    FnSearchService.searchAlbumsOverride =
        (String keyword, int page, int size) async => _page<FnAlbum>(<FnAlbum>[]);
    FnSearchService.searchArtistsOverride =
        (String keyword, int page, int size) async => _page<FnArtist>(<FnArtist>[]);

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await _submitSearch(tester, '花样');

    expect(find.textContaining('网络错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    // 点重试后成功渲染结果。
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('歌曲1'), findsOneWidget);
  });

  testWidgets('三路都空时显示未找到', (WidgetTester tester) async {
    FnSearchService.searchTracksOverride =
        (String keyword, int page, int size) async => _page<FnTrack>(<FnTrack>[]);
    FnSearchService.searchAlbumsOverride =
        (String keyword, int page, int size) async => _page<FnAlbum>(<FnAlbum>[]);
    FnSearchService.searchArtistsOverride =
        (String keyword, int page, int size) async => _page<FnArtist>(<FnArtist>[]);

    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await _submitSearch(tester, '不存在的关键词');

    expect(find.text('未找到相关结果'), findsOneWidget);
  });
}
