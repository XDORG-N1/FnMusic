import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_models.dart';

/// 搜索服务（歌曲 / 专辑 / 歌手）。
///
/// 真实 FNOS 的搜索接口是**分页响应**（`data: {list, total, ...}`），并非裸
/// 数组；解析前必须取 `data['list']`，否则按 `List` 强转会抛 TypeError，
/// 导致搜索必然失败（与其它 `/xxx/list` 分页接口一致）。
class FnSearchService {
  FnSearchService._();

  static final FnSearchService instance = FnSearchService._();

  /// 测试钩子：注入后取代真实网络请求（widget 测试用）。
  @visibleForTesting
  static Future<ApiPage<FnTrack>> Function(
      String keyword, int page, int size)? searchTracksOverride;

  @visibleForTesting
  static Future<ApiPage<FnAlbum>> Function(
      String keyword, int page, int size)? searchAlbumsOverride;

  @visibleForTesting
  static Future<ApiPage<FnArtist>> Function(
      String keyword, int page, int size)? searchArtistsOverride;

  /// 搜索歌曲（分页响应 `{list, total}`）。
  Future<ApiPage<FnTrack>> searchTracks(
    String keyword, {
    int page = 1,
    int size = 50,
  }) async {
    final Future<ApiPage<FnTrack>> Function(String, int, int)? override =
        searchTracksOverride;
    if (override != null) return override(keyword, page, size);
    final dynamic data = await ApiClient.instance.getData(
      '/search/track',
      query: <String, Object?>{'q': keyword, 'page': page, 'size': size},
    );
    return ApiPage<FnTrack>.fromJson(_asPage(data), _parseTrack);
  }

  /// 搜索专辑（分页响应 `{list, total}`）。
  Future<ApiPage<FnAlbum>> searchAlbums(
    String keyword, {
    int page = 1,
    int size = 24,
  }) async {
    final Future<ApiPage<FnAlbum>> Function(String, int, int)? override =
        searchAlbumsOverride;
    if (override != null) return override(keyword, page, size);
    final dynamic data = await ApiClient.instance.getData(
      '/search/album',
      query: <String, Object?>{'q': keyword, 'page': page, 'size': size},
    );
    return ApiPage<FnAlbum>.fromJson(_asPage(data), _parseAlbum);
  }

  /// 搜索歌手（分页响应 `{list, total}`）。
  Future<ApiPage<FnArtist>> searchArtists(
    String keyword, {
    int page = 1,
    int size = 24,
  }) async {
    final Future<ApiPage<FnArtist>> Function(String, int, int)? override =
        searchArtistsOverride;
    if (override != null) return override(keyword, page, size);
    final dynamic data = await ApiClient.instance.getData(
      '/search/artist',
      query: <String, Object?>{'q': keyword, 'page': page, 'size': size},
    );
    return ApiPage<FnArtist>.fromJson(_asPage(data), _parseArtist);
  }

  /// 测试用：直接用响应 data 解析歌曲分页（验证分页契约解析）。
  @visibleForTesting
  static ApiPage<FnTrack> parseTracksPage(Object? data) {
    return ApiPage<FnTrack>.fromJson(_asPage(data), _parseTrack);
  }

  /// 测试用：直接用响应 data 解析专辑分页（验证分页契约解析）。
  @visibleForTesting
  static ApiPage<FnAlbum> parseAlbumsPage(Object? data) {
    return ApiPage<FnAlbum>.fromJson(_asPage(data), _parseAlbum);
  }

  /// 测试用：直接用响应 data 解析歌手分页（验证分页契约解析）。
  @visibleForTesting
  static ApiPage<FnArtist> parseArtistsPage(Object? data) {
    return ApiPage<FnArtist>.fromJson(_asPage(data), _parseArtist);
  }

  /// 搜索接口返回分页结构 `{list, total, ...}`；非 Map 时按空结果处理。
  static Map<String, Object?> _asPage(dynamic data) {
    if (data is Map<Object?, Object?>) {
      return data.cast<String, Object?>();
    }
    return const <String, Object?>{};
  }

  static FnTrack _parseTrack(Object? item) {
    return FnTrack.fromJson(
      (item as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  static FnAlbum _parseAlbum(Object? item) {
    return FnAlbum.fromJson(
      (item as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  static FnArtist _parseArtist(Object? item) {
    return FnArtist.fromJson(
      (item as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }
}
