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

  /// 获取收藏歌曲完整列表（首页 / 收藏页 / Android Auto 使用）。
  ///
  /// 真实 FNOS 返回分页包裹 `{list, total}`；旧 mock/简化响应直接是数组。
  /// 两种形状都兼容解析。
  Future<List<FnTrack>> fetchFavoriteTracks() async {
    final Object? data = await _api.getData('/favorite-track/list');
    final List<Object?> raw = _listOf(data);
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 从响应 data 里取出列表：数组直接返回，`{list, total}` 取 list 字段。
  static List<Object?> _listOf(Object? data) {
    if (data is List<Object?>) return data;
    if (data is Map<Object?, Object?>) {
      return (data['list'] as List<Object?>?) ?? const <Object?>[];
    }
    return const <Object?>[];
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
