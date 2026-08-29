import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_models.dart';

/// 歌手服务。
class FnArtistService {
  FnArtistService._();

  static final FnArtistService instance = FnArtistService._();

  static const int _pageSize = 100;

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<List<FnTrack>> Function(String artistGuid)? fetchArtistTracksOverride;

  Future<ApiPage<FnArtist>> fetchArtists({int page = 1}) async {
    final dynamic data = await ApiClient.instance.getData(
      '/artist/list',
      query: <String, Object?>{'page': page, 'size': _pageSize},
    );
    return ApiPage<FnArtist>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      (Object? item) =>
          FnArtist.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
    );
  }

  /// 歌手曲目。真实 FNOS 端点参数为 `artistGUID`，分页拉全。
  Future<List<FnTrack>> fetchArtistTracks(String artistGuid) async {
    final Future<List<FnTrack>> Function(String)? override =
        fetchArtistTracksOverride;
    if (override != null) return override(artistGuid);
    if (artistGuid.trim().isEmpty) {
      throw ApiException(100002, '歌手标识缺失，请返回刷新后重试');
    }
    final List<Object?> raw = await paginateAll(
      (int page) => ApiClient.instance.getData(
        '/track/artist-detail/list',
        query: <String, Object?>{
          'artistGUID': artistGuid,
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
}
