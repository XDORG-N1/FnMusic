import 'api_client.dart';
import 'api_models.dart';

/// 曲目服务。
class FnTrackService {
  FnTrackService._();

  static final FnTrackService instance = FnTrackService._();

  static const int _pageSize = 100;

  /// 分页获取全部曲目。
  Future<ApiPage<FnTrack>> fetchTracks({int page = 1, String? sort}) async {
    final dynamic data = await ApiClient.instance.getData(
      '/track/list',
      query: <String, Object?>{
        'page': page,
        'pageSize': _pageSize,
        'sort': ?sort,
      },
    );
    return _parsePage(data);
  }

  Future<FnTrack> fetchTrackDetail(String guid) async {
    final dynamic data = await ApiClient.instance.getData(
      '/track/detail',
      query: <String, Object?>{'guid': guid},
    );
    return FnTrack.fromJson((data as Map<Object?, Object?>).cast<String, Object?>());
  }

  ApiPage<FnTrack> _parsePage(dynamic data) {
    return ApiPage<FnTrack>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      _parseTrack,
    );
  }

  static FnTrack _parseTrack(Object? item) {
    return FnTrack.fromJson((item as Map<Object?, Object?>).cast<String, Object?>());
  }
}
