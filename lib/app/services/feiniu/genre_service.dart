import 'api_client.dart';
import 'api_models.dart';

/// 流派服务。
class FnGenreService {
  FnGenreService._();

  static final FnGenreService instance = FnGenreService._();

  Future<List<FnGenre>> fetchGenres() async {
    final dynamic data = await ApiClient.instance.getData('/genre/list');
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnGenre.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 流派曲目。
  Future<List<FnTrack>> fetchGenreTracks(String genreGuid) async {
    final dynamic data = await ApiClient.instance.getData(
      '/track/genre-detail/list',
      query: <String, Object?>{'guid': genreGuid},
    );
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }
}
