import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_models.dart';

/// 风格服务。
class FnGenreService {
  FnGenreService._();

  static final FnGenreService instance = FnGenreService._();

  @visibleForTesting
  static Future<List<FnGenre>> Function()? fetchGenresOverride;

  @visibleForTesting
  static Future<List<FnTrack>> Function(String genreGuid)? fetchGenreTracksOverride;

  Future<List<FnGenre>> fetchGenres() async {
    if (fetchGenresOverride != null) return fetchGenresOverride!();
    final dynamic data = await ApiClient.instance.getData('/genre/list');
    final List<Object?> raw = listItemsOf(data);
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnGenre.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 风格曲目。真实 FNOS 端点参数为 `genreGUID`，分页拉全。
  Future<List<FnTrack>> fetchGenreTracks(String genreGuid) async {
    if (fetchGenreTracksOverride != null) {
      return fetchGenreTracksOverride!(genreGuid);
    }
    if (genreGuid.trim().isEmpty) {
      throw ApiException(100002, '风格标识缺失，请返回刷新后重试');
    }
    final List<Object?> raw = await paginateAll(
      (int page) => ApiClient.instance.getData(
        '/track/genre-detail/list',
        query: <String, Object?>{
          'genreGUID': genreGuid,
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
