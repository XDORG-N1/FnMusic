import 'api_client.dart';
import 'api_models.dart';

/// 飞牛收藏服务（服务端收藏）。
///
/// 契约：`GET /favorite-track/list` 返回曲目数组；`POST /favorite-track/create`
/// 与 `/favorite-track/delete` 携带 `{trackGuid}`。P7 收藏页扩展使用。
class FeiNiuFavoriteService {
  FeiNiuFavoriteService._();

  static final FeiNiuFavoriteService instance = FeiNiuFavoriteService._();

  final ApiClient _api = ApiClient.instance;

  /// 获取收藏歌曲 GUID 集合。
  Future<Set<String>> getFavoriteIds() async {
    final List<FnTrack> tracks = await fetchFavoriteTracks();
    return tracks.map((FnTrack t) => t.guid).toSet();
  }

  /// 获取收藏歌曲完整列表（Android Auto「收藏」节点等使用）。
  Future<List<FnTrack>> fetchFavoriteTracks() async {
    final Object? data = await _api.getData('/favorite-track/list');
    if (data is! List<Object?>) return <FnTrack>[];
    return data
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 查询某歌曲是否已收藏（媒体通知收藏按钮状态）。
  Future<bool> isFavorite(String trackGuid) async {
    final Set<String> ids = await getFavoriteIds();
    return ids.contains(trackGuid);
  }

  /// 收藏歌曲。
  Future<void> favorite(String trackGuid) async {
    await _api.postData(
      '/favorite-track/create',
      body: <String, Object?>{'trackGuid': trackGuid},
    );
  }

  /// 取消收藏。
  Future<void> unfavorite(String trackGuid) async {
    await _api.postData(
      '/favorite-track/delete',
      body: <String, Object?>{'trackGuid': trackGuid},
    );
  }
}
