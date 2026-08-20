import 'api_client.dart';
import 'api_models.dart';

/// 搜索服务（歌曲 / 专辑 / 歌手）。
class FnSearchService {
  FnSearchService._();

  static final FnSearchService instance = FnSearchService._();

  Future<List<FnTrack>> searchTracks(String keyword) async {
    final dynamic data = await ApiClient.instance.getData(
      '/search/track',
      query: <String, Object?>{'q': keyword},
    );
    return _parseTracks(data);
  }

  Future<List<FnAlbum>> searchAlbums(String keyword) async {
    final dynamic data = await ApiClient.instance.getData(
      '/search/album',
      query: <String, Object?>{'q': keyword},
    );
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnAlbum.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  Future<List<FnArtist>> searchArtists(String keyword) async {
    final dynamic data = await ApiClient.instance.getData(
      '/search/artist',
      query: <String, Object?>{'q': keyword},
    );
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnArtist.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  static List<FnTrack> _parseTracks(dynamic data) {
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }
}
