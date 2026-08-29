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

/// 音乐库（共享媒体库）。
class MockLibrary {
  MockLibrary(
    this.guid,
    this.path, {
    this.name = '',
    this.autoDownloadLyric = false,
    this.metadataPreference = 'cloud_preferred',
    int? changedAt,
  }) : contentLastChangedAt =
            changedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final String guid;
  String path;
  final String name;
  bool autoDownloadLyric;
  String metadataPreference;

  /// 内容最后变更时间（epoch 秒，与客户端归一化一致）。
  final int contentLastChangedAt;
}

class MockStore {
  MockStore._() {
    seedLibraries();
  }

  static final MockStore instance = MockStore._();

  final Set<String> favoriteTrackGuids = <String>{};
  final List<MockPlaylist> playlists = <MockPlaylist>[];
  final List<Map<String, Object?>> playHistory = <Map<String, Object?>>[];

  /// 漫游随机播放：按设备记录当前位置，避免重复推荐。
  final Map<String, int> roamCursor = <String, int>{};

  /// 音乐库列表（「音乐库管理」页）。
  final List<MockLibrary> libraries = <MockLibrary>[];

  /// 正在扫描的音乐库 guid 集合（扫描状态）。
  final Set<String> scanningGuids = <String>{};

  void seedLibraries() {
    libraries.clear();
    libraries.add(MockLibrary('lib_001', '/volume1/media/Music',
        name: 'NAS 音乐库',
        changedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400));
    libraries.add(MockLibrary('lib_002', '/volume1/downloads/音乐',
        metadataPreference: 'local_only'));
  }

  MockLibrary? libraryByGuid(String guid) {
    for (final MockLibrary lib in libraries) {
      if (lib.guid == guid) return lib;
    }
    return null;
  }

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
    scanningGuids.clear();
    seedLibraries();
  }
}
