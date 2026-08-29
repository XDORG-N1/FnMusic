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

/// 文件目录节点（文件夹选择器数据源）。
///
/// storageType：0=外接存储, 1=他人共享, 2=远程挂载, 3=存储空间, 4=应用文件。
class MockDirectory {
  MockDirectory(this.path, this.name, {this.storageType = 3});
  final String path;
  final String name;
  final int storageType;
}

class MockStore {
  MockStore._() {
    seedLibraries();
    seedDirectories();
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

  /// 文件夹选择器目录树（授权目录 + 子目录）。
  final List<MockDirectory> directories = <MockDirectory>[];

  void seedLibraries() {
    libraries.clear();
    libraries.add(MockLibrary('lib_001', '/vol1/media/Music',
        name: 'NAS 音乐库',
        changedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400));
    libraries.add(MockLibrary('lib_002', '/vol1/downloads/音乐',
        metadataPreference: 'local_only'));
  }

  /// 与真实 fnOS 一致的目录树（`/volN` 主存储 / `/vol00` 外接 / `/vol01` 共享 / `/vol02` 远程）。
  void seedDirectories() {
    directories.clear();
    directories
      ..add(MockDirectory('/vol1', 'volume1', storageType: 3))
      ..add(MockDirectory('/vol1/media', 'media'))
      ..add(MockDirectory('/vol1/media/Music', 'Music'))
      ..add(MockDirectory('/vol1/media/Movies', 'Movies'))
      ..add(MockDirectory('/vol1/downloads', 'downloads'))
      ..add(MockDirectory('/vol1/downloads/音乐', '音乐'))
      ..add(MockDirectory('/vol1/1000', '我的文件'))
      ..add(MockDirectory('/vol1/1000/我的音乐', '我的音乐'))
      ..add(MockDirectory('/vol1/@appshare', '应用文件'))
      ..add(MockDirectory('/vol00', '外接存储', storageType: 0))
      ..add(MockDirectory('/vol00/usb1', 'usb1'))
      ..add(MockDirectory('/vol01', '他人共享', storageType: 1))
      ..add(MockDirectory('/vol02', '远程挂载', storageType: 2))
      ..add(MockDirectory('/vol02/nas2', 'nas2'));
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
    seedDirectories();
  }
}
