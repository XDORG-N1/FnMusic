import 'api_client.dart';
import 'api_models.dart';

/// 歌手服务。
class FnArtistService {
  FnArtistService._();

  static final FnArtistService instance = FnArtistService._();

  static const int _pageSize = 100;

  Future<ApiPage<FnArtist>> fetchArtists({int page = 1}) async {
    final dynamic data = await ApiClient.instance.getData(
      '/artist/list',
      query: <String, Object?>{'page': page, 'pageSize': _pageSize},
    );
    return ApiPage<FnArtist>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      (Object? item) =>
          FnArtist.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
    );
  }

  /// 歌手曲目。
  Future<List<FnTrack>> fetchArtistTracks(String artistGuid) async {
    final dynamic data = await ApiClient.instance.getData(
      '/track/artist-detail/list',
      query: <String, Object?>{'guid': artistGuid},
    );
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }
}
