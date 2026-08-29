import 'api_client.dart';
import 'api_models.dart';

/// 流派服务。
class FnGenreService {
  FnGenreService._();

  static final FnGenreService instance = FnGenreService._();

  Future<List<FnGenre>> fetchGenres() async {
    final dynamic data = await ApiClient.instance.getData('/genre/list');
    final List<Object?> raw = listItemsOf(data);
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnGenre.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 流派曲目。真实 FNOS 端点参数为 `genreGUID`，分页拉全。
  Future<List<FnTrack>> fetchGenreTracks(String genreGuid) async {
    if (genreGuid.trim().isEmpty) {
      throw ApiException(100002, '流派标识缺失，请返回刷新后重试');
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
