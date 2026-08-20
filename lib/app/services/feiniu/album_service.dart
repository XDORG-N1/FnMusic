import 'api_client.dart';
import 'api_models.dart';

/// 专辑服务。
class FnAlbumService {
  FnAlbumService._();

  static final FnAlbumService instance = FnAlbumService._();

  static const int _pageSize = 100;

  Future<ApiPage<FnAlbum>> fetchAlbums({int page = 1}) async {
    final dynamic data = await ApiClient.instance.getData(
      '/album/list',
      query: <String, Object?>{'page': page, 'pageSize': _pageSize},
    );
    return ApiPage<FnAlbum>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      (Object? item) =>
          FnAlbum.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
    );
  }

  /// 专辑内曲目。
  Future<List<FnTrack>> fetchAlbumTracks(String albumGuid) async {
    final dynamic data = await ApiClient.instance.getData(
      '/track/album-detail/list',
      query: <String, Object?>{'guid': albumGuid},
    );
    return _parseTracks(data);
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
