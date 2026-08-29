import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'api_models.dart';

/// 音乐库管理服务（网页版 /music/settings?key=library 对应接口）。
///
/// 端点取自官方 Web SPA（`F.sharedLibrary.*`）：
/// - `GET /shared-library/list` / `detail`
/// - `POST /shared-library/create` / `edit` / `delete` / `scan` / `scan-all`
/// - `POST /search/index/rebuild`
/// - `GET /task/list`（fileScan 任务，用于扫描状态）
class FnLibraryService {
  FnLibraryService._();

  static final FnLibraryService instance = FnLibraryService._();

  @visibleForTesting
  static Future<List<FnLibrary>> Function()? fetchLibrariesOverride;

  @visibleForTesting
  static Future<Set<String>> Function()? activeScanGuidsOverride;

  @visibleForTesting
  static Future<void> Function({
    required String path,
    String metadataPreference,
    bool autoDownloadLyric,
  })? createLibraryOverride;

  @visibleForTesting
  static Future<void> Function({
    required String guid,
    required String path,
    String metadataPreference,
    bool autoDownloadLyric,
  })? updateLibraryOverride;

  @visibleForTesting
  static Future<void> Function(String guid)? deleteLibraryOverride;

  @visibleForTesting
  static Future<void> Function(String guid)? scanLibraryOverride;

  @visibleForTesting
  static Future<void> Function()? scanAllLibrariesOverride;

  @visibleForTesting
  static Future<void> Function()? rebuildIndexOverride;

  /// 音乐库列表。响应可能是 `{list}` / `{items}` / `{rows}` / `{libraries}`。
  Future<List<FnLibrary>> fetchLibraries() async {
    if (fetchLibrariesOverride != null) return fetchLibrariesOverride!();
    final dynamic data = await ApiClient.instance.getData('/shared-library/list');
    return _parseLibraries(data);
  }

  /// 音乐库详情。
  Future<FnLibrary?> fetchLibraryDetail(String guid) async {
    final dynamic data = await ApiClient.instance.getData(
      '/shared-library/detail',
      query: <String, Object?>{'guid': guid},
    );
    if (data is! Map) return null;
    return FnLibrary.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
    );
  }

  /// 新建音乐库。
  Future<void> createLibrary({
    required String path,
    String metadataPreference = FnMetadataPreference.cloudPreferred,
    bool autoDownloadLyric = false,
  }) async {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) throw ApiException(100002, '请填写音乐库路径');
    if (createLibraryOverride != null) {
      await createLibraryOverride!(
        path: trimmed,
        metadataPreference: metadataPreference,
        autoDownloadLyric: autoDownloadLyric,
      );
      return;
    }
    await ApiClient.instance.postData(
      '/shared-library/create',
      body: <String, Object?>{
        'path': trimmed,
        'metadataPreference': metadataPreference,
        'autoDownloadLyric': autoDownloadLyric,
      },
    );
  }

  /// 编辑音乐库。
  Future<void> updateLibrary({
    required String guid,
    required String path,
    String metadataPreference = FnMetadataPreference.cloudPreferred,
    bool autoDownloadLyric = false,
  }) async {
    final String trimmed = path.trim();
    if (guid.trim().isEmpty) {
      throw ApiException(100002, '音乐库标识缺失，请刷新后重试');
    }
    if (trimmed.isEmpty) throw ApiException(100002, '请填写音乐库路径');
    if (updateLibraryOverride != null) {
      await updateLibraryOverride!(
        guid: guid,
        path: trimmed,
        metadataPreference: metadataPreference,
        autoDownloadLyric: autoDownloadLyric,
      );
      return;
    }
    await ApiClient.instance.postData(
      '/shared-library/edit',
      body: <String, Object?>{
        'guid': guid,
        'path': trimmed,
        'metadataPreference': metadataPreference,
        'autoDownloadLyric': autoDownloadLyric,
      },
    );
  }

  /// 删除音乐库。
  Future<void> deleteLibrary(String guid) async {
    if (guid.trim().isEmpty) {
      throw ApiException(100002, '音乐库标识缺失，请刷新后重试');
    }
    if (deleteLibraryOverride != null) {
      await deleteLibraryOverride!(guid);
      return;
    }
    await ApiClient.instance.postData(
      '/shared-library/delete',
      body: <String, Object?>{'guid': guid},
    );
  }

  /// 扫描单个音乐库。
  Future<void> scanLibrary(String guid) async {
    if (guid.trim().isEmpty) {
      throw ApiException(100002, '音乐库标识缺失，请刷新后重试');
    }
    if (scanLibraryOverride != null) {
      await scanLibraryOverride!(guid);
      return;
    }
    await ApiClient.instance.postData(
      '/shared-library/scan',
      body: <String, Object?>{'guid': guid},
    );
  }

  /// 扫描全部音乐库。
  Future<void> scanAllLibraries() async {
    if (scanAllLibrariesOverride != null) {
      await scanAllLibrariesOverride!();
      return;
    }
    await ApiClient.instance.postData('/shared-library/scan-all');
  }

  /// 重建搜索索引。
  Future<void> rebuildSearchIndex() async {
    if (rebuildIndexOverride != null) {
      await rebuildIndexOverride!();
      return;
    }
    await ApiClient.instance.postData('/search/index/rebuild');
  }

  /// 正在扫描的音乐库 guid 集合（`/task/list` 中未完成的 `fileScan` 任务）。
  Future<Set<String>> activeScanLibraryGuids() async {
    if (activeScanGuidsOverride != null) return activeScanGuidsOverride!();
    final dynamic data = await ApiClient.instance.getData('/task/list');
    final List<Object?> raw = _taskListItems(data);
    final Set<String> guids = <String>{};
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final FnScanTask task = FnScanTask.fromJson(
        (item as Map<Object?, Object?>).cast<String, Object?>(),
      );
      if (task.isActiveScan && task.libraryGuid.isNotEmpty) {
        guids.add(task.libraryGuid);
      }
    }
    return guids;
  }

  List<FnLibrary> _parseLibraries(dynamic data) {
    final List<Object?>? raw = _firstList(
      data,
      const <String>['list', 'items', 'rows', 'libraries'],
    );
    if (raw == null) return const <FnLibrary>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnLibrary.fromJson(m.cast<String, Object?>()))
        .where((FnLibrary l) => l.guid.isNotEmpty && l.path.isNotEmpty)
        .toList();
  }

  List<Object?>? _firstList(dynamic data, List<String> keys) {
    if (data is List) return data;
    if (data is Map) {
      for (final String key in keys) {
        final Object? value = data[key];
        if (value is List) return value;
      }
    }
    return null;
  }

  List<Object?> _taskListItems(dynamic data) {
    final List<Object?>? list = _firstList(data, const <String>['list']);
    return list ?? const <Object?>[];
  }
}
