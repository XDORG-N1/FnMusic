import 'api_client.dart';
import 'api_models.dart';

/// 歌单服务（列表 / 详情 / CRUD）。
class FnPlaylistService {
  FnPlaylistService._();

  static final FnPlaylistService instance = FnPlaylistService._();

  Future<List<FnPlaylist>> fetchPlaylists() async {
    final dynamic data = await ApiClient.instance.getData('/playlist/list');
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnPlaylist.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 歌单内曲目。
  Future<List<FnTrack>> fetchPlaylistTracks(String playlistGuid) async {
    final dynamic data = await ApiClient.instance.getData(
      '/track/playlist-detail/list',
      query: <String, Object?>{'guid': playlistGuid},
    );
    final List<Object?> raw = (data as List<Object?>?) ?? const <Object?>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnTrack.fromJson(m.cast<String, Object?>()))
        .toList();
  }

  /// 创建歌单，返回新歌单 guid。
  Future<String> createPlaylist(String name) async {
    final dynamic data = await ApiClient.instance.postData(
      '/playlist/create',
      body: <String, Object?>{'name': name},
    );
    return ((data as Map<Object?, Object?>?)?['guid'] as String?) ?? '';
  }

  Future<void> deletePlaylist(String guid) async {
    await ApiClient.instance.postData('/playlist/delete', body: <String, Object?>{'guid': guid});
  }

  Future<void> renamePlaylist(String guid, String name) async {
    await ApiClient.instance.postData(
      '/playlist/edit',
      body: <String, Object?>{'guid': guid, 'name': name},
    );
  }

  Future<void> addTrack(String playlistGuid, String trackGuid) async {
    await ApiClient.instance.postData(
      '/playlist/add-track',
      body: <String, Object?>{'playlistGuid': playlistGuid, 'trackGuid': trackGuid},
    );
  }

  Future<void> removeTrack(String playlistGuid, String trackGuid) async {
    await ApiClient.instance.postData(
      '/playlist/remove-track',
      body: <String, Object?>{'playlistGuid': playlistGuid, 'trackGuid': trackGuid},
    );
  }
}
