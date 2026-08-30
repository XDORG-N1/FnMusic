import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/playlist_service.dart';

/// 歌单服务单元测试：不依赖 mock 服务器（本地守卫 / 覆盖钩子）。
void main() {
  setUp(() {
    FnPlaylistService.fetchPlaylistsOverride = null;
    FnPlaylistService.fetchPlaylistTracksOverride = null;
    FnPlaylistService.createPlaylistOverride = null;
    FnPlaylistService.deletePlaylistOverride = null;
    FnPlaylistService.renamePlaylistOverride = null;
    FnPlaylistService.addTrackOverride = null;
    FnPlaylistService.removeTrackOverride = null;
  });

  tearDown(() {
    FnPlaylistService.fetchPlaylistsOverride = null;
    FnPlaylistService.fetchPlaylistTracksOverride = null;
    FnPlaylistService.createPlaylistOverride = null;
    FnPlaylistService.deletePlaylistOverride = null;
    FnPlaylistService.renamePlaylistOverride = null;
    FnPlaylistService.addTrackOverride = null;
    FnPlaylistService.removeTrackOverride = null;
  });

  group('本地守卫（不发起网络请求）', () {
    test('fetchPlaylistTracks 空 guid → 100002', () async {
      await expectLater(
        FnPlaylistService.instance.fetchPlaylistTracks('   '),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
    });

    test('addTrack 空参数 → 100002', () async {
      await expectLater(
        FnPlaylistService.instance.addTrack('', 't1'),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
      await expectLater(
        FnPlaylistService.instance.addTrack('p1', '  '),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
    });

    test('removeTrack 空参数 → 100002', () async {
      await expectLater(
        FnPlaylistService.instance.removeTrack('', 't1'),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
      await expectLater(
        FnPlaylistService.instance.removeTrack('p1', ''),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
    });
  });

  group('覆盖钩子行为', () {
    test('fetchPlaylists 走覆盖钩子', () async {
      final List<FnPlaylist> playlists = <FnPlaylist>[
        const FnPlaylist(guid: 'pl_1', name: '旅行', trackCount: 3),
      ];
      FnPlaylistService.fetchPlaylistsOverride = () async => playlists;
      expect(await FnPlaylistService.instance.fetchPlaylists(), playlists);
    });

    test('fetchPlaylistTracks 走覆盖钩子并透传 playlistGuid', () async {
      String? seen;
      FnPlaylistService.fetchPlaylistTracksOverride = (String guid) async {
        seen = guid;
        return <FnTrack>[];
      };
      await FnPlaylistService.instance.fetchPlaylistTracks('pl_9');
      expect(seen, 'pl_9');
    });

    test('createPlaylist 走覆盖钩子并透传名称', () async {
      String? seen;
      FnPlaylistService.createPlaylistOverride = (String name) async {
        seen = name;
        return 'pl_new';
      };
      expect(
        await FnPlaylistService.instance.createPlaylist('我的精选'),
        'pl_new',
      );
      expect(seen, '我的精选');
    });

    test('deletePlaylist / renamePlaylist 走覆盖钩子并透传参数', () async {
      String? deleted;
      String? renamedGuid;
      String? renamedName;
      FnPlaylistService.deletePlaylistOverride = (String guid) async {
        deleted = guid;
      };
      FnPlaylistService.renamePlaylistOverride = (String guid, String name) async {
        renamedGuid = guid;
        renamedName = name;
      };
      await FnPlaylistService.instance.deletePlaylist('pl_x');
      expect(deleted, 'pl_x');
      await FnPlaylistService.instance.renamePlaylist('pl_y', '新名');
      expect(renamedGuid, 'pl_y');
      expect(renamedName, '新名');
    });

    test('addTrack 走覆盖钩子并透传 (playlistGuid, trackGuid)', () async {
      String? seenPl;
      String? seenTrack;
      FnPlaylistService.addTrackOverride = (String playlistGuid, String trackGuid) async {
        seenPl = playlistGuid;
        seenTrack = trackGuid;
      };
      await FnPlaylistService.instance.addTrack('pl_1', 'trk_2');
      expect(seenPl, 'pl_1');
      expect(seenTrack, 'trk_2');
    });

    test('removeTrack 走覆盖钩子并透传 (playlistGuid, trackGuid)', () async {
      String? seenPl;
      String? seenTrack;
      FnPlaylistService.removeTrackOverride = (String playlistGuid, String trackGuid) async {
        seenPl = playlistGuid;
        seenTrack = trackGuid;
      };
      await FnPlaylistService.instance.removeTrack('pl_1', 'trk_2');
      expect(seenPl, 'pl_1');
      expect(seenTrack, 'trk_2');
    });
  });
}
