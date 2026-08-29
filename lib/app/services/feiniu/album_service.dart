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
        // 真实 FNOS 分页参数为 `size`（`pageSize` 不生效）。
        'size': _pageSize,
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
  ///
  /// 真实 FNOS 端点 `/track/album-detail/list` 参数为 `albumGUID`（非 `guid`），
  /// 分页结构 `{list, total, sort}`，默认每页 50，需逐页拉全。
  Future<List<FnTrack>> fetchAlbumTracks(String albumGuid) async {
    final Future<List<FnTrack>> Function(String)? override =
        fetchAlbumTracksOverride;
    if (override != null) return override(albumGuid);
    if (albumGuid.trim().isEmpty) {
      // 真实 FNOS 对空 albumGUID 返回 100002（InvalidArgs）；本地拦截。
      throw ApiException(100002, '专辑标识缺失，请返回刷新后重试');
    }
    final List<Object?> raw = await paginateAll(
      (int page) => ApiClient.instance.getData(
        '/track/album-detail/list',
        query: <String, Object?>{
          'albumGUID': albumGuid,
          'page': page,
          'size': 100,
        },
      ),
    );
    return _parseTracks(raw);
  }

  static List<FnTrack> _parseTracks(List<Object?> raw) {
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }
}
