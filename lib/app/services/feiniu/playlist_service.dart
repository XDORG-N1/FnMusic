import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_models.dart';

/// 歌单服务（列表 / 详情 / CRUD）。
class FnPlaylistService {
  FnPlaylistService._();

  static final FnPlaylistService instance = FnPlaylistService._();

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<List<FnPlaylist>> Function()? fetchPlaylistsOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<List<FnTrack>> Function(String playlistGuid)?
      fetchPlaylistTracksOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<String> Function(String name)? createPlaylistOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<void> Function(String guid)? deletePlaylistOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<void> Function(String guid, String name)?
      renamePlaylistOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<void> Function(String playlistGuid, String trackGuid)?
      addTrackOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<void> Function(String playlistGuid, String trackGuid)?
      removeTrackOverride;

  /// 获取歌单列表。
  ///
  /// 真实 FNOS 返回分页包裹 `{list, total}`；旧 mock/简化响应直接是数组。
  /// 两种形状都兼容解析。
  Future<List<FnPlaylist>> fetchPlaylists() async {
    final Future<List<FnPlaylist>> Function()? override =
        fetchPlaylistsOverride;
    if (override != null) return override();
    final dynamic data = await ApiClient.instance.getData('/playlist/list');
    final List<Object?> raw = listItemsOf(data);
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnPlaylist.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 歌单内曲目。真实 FNOS 端点参数为 `playlistGUID`，分页拉全。
  Future<List<FnTrack>> fetchPlaylistTracks(String playlistGuid) async {
    if (playlistGuid.trim().isEmpty) {
      throw ApiException(100002, '歌单标识缺失，请返回刷新后重试');
    }
    final Future<List<FnTrack>> Function(String)? override =
        fetchPlaylistTracksOverride;
    if (override != null) return override(playlistGuid);
    final List<Object?> raw = await paginateAll(
      (int page) => ApiClient.instance.getData(
        '/track/playlist-detail/list',
        query: <String, Object?>{
          'playlistGUID': playlistGuid,
          'page': page,
          'size': 100,
        },
      ),
    );
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 创建歌单，返回新歌单 guid。
  Future<String> createPlaylist(String name) async {
    final Future<String> Function(String)? override = createPlaylistOverride;
    if (override != null) return override(name);
    final dynamic data = await ApiClient.instance.postData(
      '/playlist/create',
      body: <String, Object?>{'name': name},
    );
    return ((data as Map<Object?, Object?>?)?['guid'] as String?) ?? '';
  }

  Future<void> deletePlaylist(String guid) async {
    final Future<void> Function(String)? override = deletePlaylistOverride;
    if (override != null) return override(guid);
    await ApiClient.instance
        .postData('/playlist/delete', body: <String, Object?>{'guid': guid});
  }

  Future<void> renamePlaylist(String guid, String name) async {
    final Future<void> Function(String, String)? override =
        renamePlaylistOverride;
    if (override != null) return override(guid, name);
    await ApiClient.instance.postData(
      '/playlist/edit',
      body: <String, Object?>{'guid': guid, 'name': name},
    );
  }

  /// 添加歌曲到歌单。
  ///
  /// 真实 FNOS 契约：body 为 `{guid, trackGUIDs:[...]}`（数组）。
  Future<void> addTrack(String playlistGuid, String trackGuid) async {
    if (playlistGuid.trim().isEmpty || trackGuid.trim().isEmpty) {
      throw ApiException(100002, '歌单或曲目标识缺失');
    }
    final Future<void> Function(String, String)? override = addTrackOverride;
    if (override != null) return override(playlistGuid, trackGuid);
    await ApiClient.instance.postData(
      '/playlist/add-track',
      body: <String, Object?>{
        'guid': playlistGuid,
        'trackGUIDs': <String>[trackGuid],
      },
    );
  }

  /// 从歌单移除歌曲。
  ///
  /// 真实 FNOS 契约：body 为 `{guid, trackGUIDs:[...]}`（数组）。
  Future<void> removeTrack(String playlistGuid, String trackGuid) async {
    if (playlistGuid.trim().isEmpty || trackGuid.trim().isEmpty) {
      throw ApiException(100002, '歌单或曲目标识缺失');
    }
    final Future<void> Function(String, String)? override = removeTrackOverride;
    if (override != null) return override(playlistGuid, trackGuid);
    await ApiClient.instance.postData(
      '/playlist/remove-track',
      body: <String, Object?>{
        'guid': playlistGuid,
        'trackGUIDs': <String>[trackGuid],
      },
    );
  }
}
