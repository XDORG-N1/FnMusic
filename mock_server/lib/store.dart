/// Mock 内存可变存储：收藏 / 歌单 / 播放历史 / 漫游设备。
library;

class MockPlaylist {
  MockPlaylist(this.guid, this.name)
      : createdAt = DateTime.now().millisecondsSinceEpoch;
  final String guid;
  String name;
  final int createdAt;
  final List<String> trackGuids = <String>[];
}

class MockStore {
  MockStore._();

  static final MockStore instance = MockStore._();

  final Set<String> favoriteTrackGuids = <String>{};
  final List<MockPlaylist> playlists = <MockPlaylist>[];
  final List<Map<String, Object?>> playHistory = <Map<String, Object?>>[];

  /// 漫游随机播放：按设备记录当前位置，避免重复推荐。
  final Map<String, int> roamCursor = <String, int>{};

  MockPlaylist createPlaylist(String name) {
    final String guid = 'pl_${playlists.length + 1}';
    final MockPlaylist playlist = MockPlaylist(guid, name);
    playlists.add(playlist);
    return playlist;
  }

  /// 重置全部可变状态（开发用）。
  void reset() {
    favoriteTrackGuids.clear();
    playlists.clear();
    playHistory.clear();
    roamCursor.clear();
  }
}
