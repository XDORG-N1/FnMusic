import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/album_service.dart';
import 'package:fnmusic/app/services/feiniu/track_service.dart';
import 'package:fnmusic/app/services/player/stream_cache_service.dart';
import 'package:fnmusic/pages/library/albums_page.dart';

import '../../helpers/fake_engine.dart';

FnAlbum _album(
  int i, {
  String? name,
  String? coverId,
  int? trackCount,
  int? year,
}) {
  return FnAlbum.fromJson(<String, Object?>{
    'guid': 'album-$i',
    'name': name ?? '专辑$i',
    'coverId': coverId,
    'trackCount': trackCount,
    'year': year,
  });
}

/// 默认每页 20 条，配合 `ApiPage.hasMore = (page*pageSize) < total` 计算翻页。
ApiPage<FnAlbum> _albumPage(
  List<FnAlbum> albums, {
  int total = 0,
  int pageSize = 20,
  int page = 1,
}) {
  final int t = total > 0 ? total : albums.length;
  return ApiPage<FnAlbum>(
    list: albums,
    total: t,
    page: page,
    pageSize: pageSize,
  );
}

void main() {
  late FakeEngine fakeMain;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ApiClient.instance.setServerUrl('http://test');
    StreamCacheService.instance.enabled = false;
    fakeMain = FakeEngine();
    setupPlayerForTest(fakeMain);
    FnAlbumService.fetchAlbumsOverride = null;
    FnAlbumService.fetchAlbumTracksOverride = null;
    FnTrackService.fetchOverride = null;
  });

  tearDown(() {
    FnAlbumService.fetchAlbumsOverride = null;
    FnAlbumService.fetchAlbumTracksOverride = null;
    FnTrackService.fetchOverride = null;
  });

  testWidgets('专辑网格渲染名称、封面占位字母与首数', (WidgetTester tester) async {
    FnAlbumService.fetchAlbumsOverride =
        (int page, String? sort) async => _albumPage(<FnAlbum>[
              _album(1, trackCount: 12, year: 2001),
              _album(2, name: 'B 盘', trackCount: 3),
            ]);

    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pumpAndSettle();

    expect(find.text('专辑1'), findsOneWidget);
    expect(find.text('B 盘'), findsOneWidget);
    // 无封面专辑显示首字母占位。
    expect(find.text('专'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('12首'), findsOneWidget);
    expect(find.text('3首'), findsOneWidget);
  });

  testWidgets('点按专辑进入详情页', (WidgetTester tester) async {
    FnAlbumService.fetchAlbumsOverride =
        (int page, String? sort) async =>
            _albumPage(<FnAlbum>[_album(1, coverId: 'c1', trackCount: 2)]);
    FnAlbumService.fetchAlbumTracksOverride = (String albumGuid) async =>
        <FnTrack>[_track(1), _track(2)];

    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('专辑1'));
    await tester.pumpAndSettle();

    // 进入详情页：出现「歌曲」区与曲目。
    expect(find.text('歌曲'), findsOneWidget);
    expect(find.text('歌曲1'), findsOneWidget);
  });

  testWidgets('排序面板切换排序模式并重新加载', (WidgetTester tester) async {
    final List<(int, String?)> calls = <(int, String?)>[];
    FnAlbumService.fetchAlbumsOverride = (int page, String? sort) async {
      calls.add((page, sort));
      return _albumPage(<FnAlbum>[_album(1)]);
    };

    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pumpAndSettle();
    expect(calls.single.$2, 'newTrackAddedAt,desc');

    // 打开排序面板，选择「专辑名」。
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.text('专辑名'));
    await tester.pumpAndSettle();
    expect(calls.last.$2, 'name,desc');

    // 切换升序。
    await tester.tap(find.text('升序'));
    await tester.pumpAndSettle();
    expect(calls.last.$2, 'name,asc');
  });

  testWidgets('滚动到底部加载下一页', (WidgetTester tester) async {
    final List<int> pages = <int>[];
    FnAlbumService.fetchAlbumsOverride = (int page, String? sort) async {
      pages.add(page);
      if (page == 1) {
        // 每页 20 → page1 的 hasMore=(1*20)<25 为真。
        return _albumPage(
          List<FnAlbum>.generate(20, (int i) => _album(i)),
          total: 25,
        );
      }
      // page2 的 hasMore=(2*20)<25 为假。
      return _albumPage(
        List<FnAlbum>.generate(5, (int i) => _album(20 + i)),
        total: 25,
        page: 2,
      );
    };

    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pumpAndSettle();

    // 滚动到底部触发加载更多。
    await tester.drag(find.byType(GridView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expect(pages, <int>[1, 2]);

    // 继续滚动直到第二页内容可见（懒加载网格需滚到对应行）。
    await tester.scrollUntilVisible(
      find.text('专辑20'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('专辑20'), findsOneWidget);
  });

  testWidgets('下拉刷新重新加载第一页', (WidgetTester tester) async {
    int page1Calls = 0;
    FnAlbumService.fetchAlbumsOverride = (int page, String? sort) async {
      if (page == 1) page1Calls++;
      return _albumPage(<FnAlbum>[_album(1), _album(2), _album(3)]);
    };

    await tester.pumpWidget(const MaterialApp(home: AlbumsPage()));
    await tester.pumpAndSettle();
    expect(page1Calls, 1);

    // 下拉触发 RefreshIndicator。
    await tester.fling(
        find.byType(GridView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(page1Calls, greaterThanOrEqualTo(2));
  });
}

FnTrack _track(int i) {
  return FnTrack.fromJson(<String, Object?>{
    'guid': 'track-$i',
    'title': '歌曲$i',
    'duration': 210000,
    'artists': <Object?>[
      <String, Object?>{'guid': 'artist-$i', 'name': '歌手$i'},
    ],
    'album': <String, Object?>{'guid': 'album-$i', 'name': '专辑$i'},
  });
}
