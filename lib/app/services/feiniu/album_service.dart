import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_models.dart';

/// 专辑服务。
class FnAlbumService {
  FnAlbumService._();

  static final FnAlbumService instance = FnAlbumService._();

  static const int _pageSize = 100;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<ApiPage<FnAlbum>> Function(int page, String? sort)?
      fetchAlbumsOverride;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<List<FnTrack>> Function(String albumGuid)?
      fetchAlbumTracksOverride;

  /// 分页获取专辑。真实 FNOS 支持 `sort`（如 `newTrackAddedAt,desc` 最新添加）。
  Future<ApiPage<FnAlbum>> fetchAlbums({int page = 1, String? sort}) async {
    final Future<ApiPage<FnAlbum>> Function(int, String?)? override =
        fetchAlbumsOverride;
    if (override != null) return override(page, sort);
    final dynamic data = await ApiClient.instance.getData(
      '/album/list',
      query: <String, Object?>{
        'page': page,
        'pageSize': _pageSize,
        'sort': ?sort,
      },
    );
    return ApiPage<FnAlbum>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      (Object? item) =>
          FnAlbum.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
    );
  }

  /// 专辑内曲目。
  Future<List<FnTrack>> fetchAlbumTracks(String albumGuid) async {
    final Future<List<FnTrack>> Function(String)? override =
        fetchAlbumTracksOverride;
    if (override != null) return override(albumGuid);
    final dynamic data = await ApiClient.instance.getData(
      '/track/album-detail/list',
      query: <String, Object?>{'guid': albumGuid},
    );
    return _parseTracks(data);
  }

  static List<FnTrack> _parseTracks(dynamic data) {
    final List<Object?> raw = listItemsOf(data);
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }
}
