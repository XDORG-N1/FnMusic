/// FNOS 音乐 API 数据模型。
///
/// 响应统一包装为 `{code, msg, data}`（真实 FNOS 业务字段为 `msg`；兼容读取 `message`）。
library;

/// 从响应 `data` 字段取列表：数组直接返回，`{list, total}` 分页结构取 `list`。
///
/// 真实 FNOS 的列表接口统一返回分页包裹 `{list, total}`，个别接口 / 旧版本
/// 返回裸数组。旧实现按裸 `List` 强转在分页结构下抛 TypeError（如专辑 / 歌手 /
/// 风格 / 歌单详情曲目），这里两种形态都兼容。
List<Object?> listItemsOf(Object? data) {
  if (data is List) return data;
  if (data is Map) {
    final Object? list = data['list'];
    if (list is List) return list;
  }
  return const <Object?>[];
}

/// 从分页响应 `data` 取总数：`{total, list}` 结构，缺失时回退列表长度。
int totalOf(Object? data) {
  if (data is Map) {
    final int? total = (data['total'] as num?)?.toInt();
    if (total != null && total >= 0) return total;
  }
  return listItemsOf(data).length;
}

/// 分页拉取全部列表项：循环调用 [fetchPage]（入参 page，从 1 起）直到收集够
/// `total` 或某一页为空。真实 FNOS 详情曲目端点返回 `{list, total, sort}`，
/// 默认每页 50（size 上限），需逐页拉全。
Future<List<Object?>> paginateAll(
  Future<dynamic> Function(int page) fetchPage,
) async {
  final List<Object?> all = <Object?>[];
  int page = 1;
  while (true) {
    final dynamic data = await fetchPage(page);
    final List<Object?> items = listItemsOf(data);
    if (items.isEmpty) break;
    all.addAll(items);
    if (all.length >= totalOf(data)) break;
    page++;
  }
  return all;
}

/// API 响应包装。
class ApiResponse<T> {
  const ApiResponse({required this.code, required this.message, required this.data});

  final int code;
  final String message;
  final T? data;

  bool get isOk => code == 0;

  factory ApiResponse.fromJson(
    Map<String, Object?> json,
    T Function(Object? data) parse,
  ) {
    return ApiResponse<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      // 真实 FNOS 用 `msg`；mock/旧响应用 `message`，兼容读取。
      message: json['msg'] as String? ?? json['message'] as String? ?? '',
      data: json.containsKey('data') ? parse(json['data']) : null,
    );
  }
}

/// 分页数据包装。
class ApiPage<T> {
  const ApiPage({required this.list, required this.total, required this.page, required this.pageSize});

  final List<T> list;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => (page * pageSize) < total;

  factory ApiPage.fromJson(
    Map<String, Object?> json,
    T Function(Object? item) parse,
  ) {
    final List<Object?> raw = (json['list'] as List<Object?>?) ?? const <Object?>[];
    return ApiPage<T>(
      list: raw.map(parse).toList(),
      total: (json['total'] as num?)?.toInt() ?? raw.length,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? raw.length,
    );
  }
}

/// 歌手。
class FnArtist {
  const FnArtist({required this.guid, required this.name, this.coverId});

  final String guid;
  final String name;
  final String? coverId;

  factory FnArtist.fromJson(Map<String, Object?> json) {
    return FnArtist(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coverId: json['coverId'] as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'guid': guid,
        'name': name,
        if (coverId != null) 'coverId': coverId,
      };
}

/// 专辑。
class FnAlbum {
  const FnAlbum({
    required this.guid,
    required this.name,
    this.coverId,
    this.year,
    this.trackCount,
  });

  final String guid;
  final String name;
  final String? coverId;
  final int? year;

  /// 专辑内曲目数（真实 FNOS 返回 trackCount；mock/旧数据可为空）。
  final int? trackCount;

  factory FnAlbum.fromJson(Map<String, Object?> json) {
    return FnAlbum(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coverId: json['coverId'] as String?,
      year: (json['year'] as num?)?.toInt(),
      trackCount: (json['trackCount'] as num?)?.toInt(),
    );
  }
}

/// 风格。
class FnGenre {
  const FnGenre({
    required this.guid,
    required this.name,
    this.trackCount = 0,
    this.coverId,
  });

  final String guid;
  final String name;

  /// 该风格下曲目数（真实 FNOS `/genre/list` 返回 `trackCount`）。
  final int trackCount;

  /// 风格封面（真实 FNOS `/genre/list` 返回 `coverId`）。
  final String? coverId;

  factory FnGenre.fromJson(Map<String, Object?> json) {
    return FnGenre(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      coverId: json['coverId'] as String?,
    );
  }
}

/// 音乐库元数据偏好（真实 FNOS `/shared-library` 的 `metadataPreference` 枚举）。
abstract final class FnMetadataPreference {
  static const String localPreferred = 'local_preferred';
  static const String cloudPreferred = 'cloud_preferred';
  static const String localOnly = 'local_only';
}

/// 音乐库（共享媒体库，网页版「音乐库管理」）。
///
/// 字段对齐真实 FNOS `/shared-library/list`（经官方 SPA 逆向）：
/// `{guid, path, name, autoDownloadLyric, metadataPreference, accessStatus,
/// contentLastChangedAt, coverIds}`。
class FnLibrary {
  const FnLibrary({
    required this.guid,
    required this.path,
    this.name = '',
    this.autoDownloadLyric = false,
    this.metadataPreference = FnMetadataPreference.cloudPreferred,
    this.accessStatus = 0,
    this.contentLastChangedAt = 0,
    this.coverIds = const <String>[],
  });

  final String guid;
  final String path;
  final String name;
  final bool autoDownloadLyric;

  /// `local_preferred` / `cloud_preferred` / `local_only`。
  final String metadataPreference;
  final int accessStatus;

  /// 内容最后变更时间（epoch 秒；服务端也可能回毫秒，解析时归一化）。
  final int contentLastChangedAt;
  final List<String> coverIds;

  /// 展示名：显式 name 优先，否则取路径末段。
  String get displayName {
    final String trimmed = name.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final String norm = path.replaceAll('\\', '/').trimRight();
    final List<String> segs =
        norm.split('/').where((String s) => s.isNotEmpty).toList();
    return segs.isEmpty ? path : segs.last;
  }

  /// 内容最后变更时间（毫秒时间戳；0 / 无效 → null）。
  DateTime? get lastChangedAt {
    if (contentLastChangedAt <= 0) return null;
    final int seconds =
        contentLastChangedAt > 1000000000000
            ? (contentLastChangedAt / 1000).round()
            : contentLastChangedAt;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  factory FnLibrary.fromJson(Map<String, Object?> json) {
    final Object? rawChanged = json['contentLastChangedAt'];
    final int changed =
        rawChanged is num ? rawChanged.toInt() : (int.tryParse('$rawChanged') ?? 0);
    final List<Object?> rawCovers = json['coverIds'] is List
        ? json['coverIds']! as List<Object?>
        : const <Object?>[];
    return FnLibrary(
      guid: json['guid'] as String? ?? '',
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      autoDownloadLyric: json['autoDownloadLyric'] as bool? ?? false,
      metadataPreference: json['metadataPreference'] as String? ??
          FnMetadataPreference.cloudPreferred,
      accessStatus: (json['accessStatus'] as num?)?.toInt() ?? 0,
      contentLastChangedAt: changed,
      coverIds: rawCovers
          .whereType<String>()
          .map((String c) => c.trim())
          .where((String c) => c.isNotEmpty)
          .toList(),
    );
  }
}

/// 扫描任务（`/task/list` 中的 `fileScan` 类型），用于展示音乐库扫描状态。
class FnScanTask {
  const FnScanTask({
    required this.guid,
    required this.libraryGuid,
    required this.type,
    required this.done,
    required this.cancelling,
    required this.createdAt,
  });

  final String guid;
  final String libraryGuid;
  final String type;
  final bool done;
  final bool cancelling;
  final int createdAt;

  bool get isActiveScan => type == 'fileScan' && !done;

  factory FnScanTask.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> ext = _mapField(json['ext']);
    final Object? rawCreated = json['createdAt'];
    return FnScanTask(
      guid: json['guid'] as String? ?? '',
      libraryGuid: ext['libraryGUID']?.toString() ?? '',
      type: json['type'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      cancelling: json['cancelling'] as bool? ?? false,
      createdAt: rawCreated is num ? rawCreated.toInt() : (int.tryParse('$rawCreated') ?? 0),
    );
  }
}

Map<String, Object?> _mapField(Object? value) {
  if (value is Map<Object?, Object?>) return value.cast<String, Object?>();
  return const <String, Object?>{};
}

/// 文件目录节点（文件夹选择器数据源）。
///
/// 来自 `GET /app-center/authed-dir/list`（授权目录根）与
/// `GET /app-center/authed-dir/sub/list?parent=`（子目录），字段 `{path, name, storageType}`。
/// 子目录响应通常只有 `{path, name}`，storageType 缺失时按 3（存储空间）兜底。
class FnDirectory {
  const FnDirectory({
    required this.path,
    required this.name,
    this.storageType = 3,
  });

  final String path;
  final String name;

  /// 0=外接存储, 1=他人共享, 2=远程挂载, 3=存储空间, 4=应用文件。
  final int storageType;

  factory FnDirectory.fromJson(Map<String, Object?> json) {
    return FnDirectory(
      path: json['path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      storageType: (json['storageType'] as num?)?.toInt() ?? 3,
    );
  }
}

/// fnOS 路径语义化（对齐网页版 pathFormatter）。
///
/// 顶层目录前缀（真实 fnOS）：
/// - `/vol1`…（`vol` + 数字，主存储）→ `存储空间 {id}`
/// - `/vol1/{uid}/…` → `存储空间 {id}/我的文件|用户{uid} 的文件/…`
/// - `/vol1/@appshare` → `应用文件`，`/vol1/@team` → `团队文件`
/// - `/vol00…` → `外接存储`，`/vol01…` → `他人共享`，`/vol02…` → `远程挂载`
/// - 其余无法识别 → 原样返回。
String semanticPathOf(String raw) {
  final String p = raw.replaceAll('\\', '/').trimRight();
  final List<String> segs = p.split('/').where((String s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return raw;
  final String first = segs.first;

  // 外接存储 / 他人共享 / 远程挂载（顶层即特例前缀）。
  final Map<String, String> topLabels = <String, String>{
    'vol00': '外接存储',
    'vol01': '他人共享',
    'vol02': '远程挂载',
  };
  for (final MapEntry<String, String> entry in topLabels.entries) {
    if (first.startsWith(entry.key)) {
      final String rest = segs.sublist(1).join('/');
      return rest.isEmpty ? entry.value : '${entry.value}/$rest';
    }
  }

  // 主存储 `vol{N}`。
  if (first.startsWith('vol') && first.length > 3) {
    final int? id = int.tryParse(first.substring(3));
    if (id != null) {
      final String base = '存储空间 $id';
      if (segs.length >= 2) {
        final String second = segs[1];
        if (second == '@appshare') {
          final String rest = segs.sublist(2).join('/');
          return rest.isEmpty ? '应用文件' : '应用文件/$rest';
        }
        if (second == '@team') {
          final String rest = segs.sublist(2).join('/');
          return rest.isEmpty ? '团队文件' : '团队文件/$rest';
        }
        final int? uid = int.tryParse(second);
        if (uid != null) {
          final String rest = segs.sublist(2).join('/');
          // 1000 为 fnOS 默认管理员 uid，对应「我的文件」。
          final String user = uid == 1000 ? '我的文件' : '用户$uid 的文件';
          return rest.isEmpty ? '$base/$user' : '$base/$user/$rest';
        }
        final String rest = segs.sublist(1).join('/');
        return '$base/$rest';
      }
      return base;
    }
  }
  return raw;
}

/// 音频规格。
class FnAudioSpec {
  const FnAudioSpec({
    this.bitDepth,
    this.sampleRate,
    this.channel,
    this.bitrate,
    this.codec,
    this.format,
    this.duration,
    this.size,
    this.path,
  });

  final int? bitDepth;
  final int? sampleRate;
  final int? channel;
  final int? bitrate;
  final String? codec;
  final String? format;
  final int? duration;
  final int? size;

  /// 物理文件路径（CUE 整轨曲目共享同一路径，用于分组计算偏移）。
  final String? path;

  factory FnAudioSpec.fromJson(Map<String, Object?> json) {
    return FnAudioSpec(
      bitDepth: (json['bitDepth'] as num?)?.toInt(),
      sampleRate: (json['sampleRate'] as num?)?.toInt(),
      channel: (json['channel'] as num?)?.toInt(),
      bitrate: (json['bitrate'] as num?)?.toInt(),
      codec: json['codec'] as String?,
      format: json['format'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      size: (json['size'] as num?)?.toInt(),
      path: json['path'] as String?,
    );
  }
}

/// 曲目（对应 `/track/list` 等返回的单曲）。
class FnTrack {
  const FnTrack({
    required this.guid,
    required this.title,
    this.coverId,
    this.year,
    this.discNo,
    this.trackNo,
    this.duration,
    this.isCue = false,
    this.album,
    this.artists = const <FnArtist>[],
    this.genres = const <FnGenre>[],
    this.isFavorite = false,
    this.hasLyric = false,
    this.audioSpec,
  });

  final String guid;
  final String title;
  final String? coverId;
  final int? year;
  final int? discNo;
  final int? trackNo;

  /// 时长（毫秒）。
  final int? duration;
  final bool isCue;
  final FnAlbum? album;
  final List<FnArtist> artists;
  final List<FnGenre> genres;
  final bool isFavorite;
  final bool hasLyric;
  final FnAudioSpec? audioSpec;

  factory FnTrack.fromJson(Map<String, Object?> json) {
    return FnTrack(
      guid: json['guid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      coverId: json['coverId'] as String?,
      year: (json['year'] as num?)?.toInt(),
      discNo: (json['discNo'] as num?)?.toInt(),
      trackNo: (json['trackNo'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toInt(),
      isCue: json['isCue'] as bool? ?? false,
      album: json['album'] is Map<String, Object?>
          ? FnAlbum.fromJson((json['album'] as Map<Object?, Object?>).cast<String, Object?>())
          : null,
      artists: _parseList<FnArtist>(json['artists'], FnArtist.fromJson),
      genres: _parseList<FnGenre>(json['genres'], FnGenre.fromJson),
      isFavorite: json['isFavorite'] as bool? ?? false,
      hasLyric: json['hasLyric'] as bool? ?? false,
      audioSpec: json['audioSpec'] is Map<String, Object?>
          ? FnAudioSpec.fromJson((json['audioSpec'] as Map<Object?, Object?>).cast<String, Object?>())
          : null,
    );
  }

  static List<T> _parseList<T>(
    Object? raw,
    T Function(Map<String, Object?>) parse,
  ) {
    if (raw is! List<Object?>) return <T>[];
    return raw
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) => parse(m.cast<String, Object?>()))
        .toList();
  }
}

/// 歌单。
class FnPlaylist {
  const FnPlaylist({
    required this.guid,
    required this.name,
    this.coverId,
    this.createdAt,
    this.trackCount,
  });

  final String guid;
  final String name;
  final String? coverId;
  final int? createdAt;
  final int? trackCount;

  factory FnPlaylist.fromJson(Map<String, Object?> json) {
    return FnPlaylist(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coverId: json['coverId'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt(),
      trackCount: (json['trackCount'] as num?)?.toInt(),
    );
  }
}

/// 漫游链中的一首歌（真实 FNOS 返回 roamId + track 包裹）。
class FnRoamTrack {
  const FnRoamTrack({required this.roamId, required this.track});

  final String roamId;
  final FnTrack track;

  factory FnRoamTrack.fromJson(Map<String, Object?> json) {
    return FnRoamTrack(
      roamId: json['roamId'] as String? ?? '',
      track: FnTrack.fromJson(_asMap(json['track'])),
    );
  }
}

/// 漫游起始响应：`data.current`（必填）+ `data.next`（可选）。
class FnRoamStartResponse {
  const FnRoamStartResponse({required this.current, this.next});

  final FnRoamTrack current;
  final FnRoamTrack? next;

  factory FnRoamStartResponse.fromJson(Map<String, Object?> json) {
    return FnRoamStartResponse(
      current: FnRoamTrack.fromJson(_asMap(json['current'])),
      next: json['next'] is Map<Object?, Object?>
          ? FnRoamTrack.fromJson(_asMap(json['next']))
          : null,
    );
  }
}

/// 漫游续播响应：`data.next`（可选）。
class FnRoamNextResponse {
  const FnRoamNextResponse({this.previous, this.current, this.next});

  final FnRoamTrack? previous;
  final FnRoamTrack? current;
  final FnRoamTrack? next;

  factory FnRoamNextResponse.fromJson(Map<String, Object?> json) {
    FnRoamTrack? parseTrack(Object? key) =>
        json[key] is Map<Object?, Object?>
            ? FnRoamTrack.fromJson(_asMap(json[key]))
            : null;
    return FnRoamNextResponse(
      previous: parseTrack('previous'),
      current: parseTrack('current'),
      next: parseTrack('next'),
    );
  }
}

/// 登录结果。
class FnLoginResult {
  const FnLoginResult({required this.token, required this.userId, required this.name});

  final String token;
  final String userId;
  final String name;

  factory FnLoginResult.fromJson(Map<String, Object?> data) {
    final Map<String, Object?> user =
        (data['user'] as Map<Object?, Object?>?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return FnLoginResult(
      // 真实 FNOS 返回 userToken；mock 返回 token，兼容读取。
      token: data['userToken'] as String? ?? data['token'] as String? ?? '',
      // 真实 FNOS 用户标识为 guid；mock 用 userId。
      userId: user['guid'] as String? ?? user['userId'] as String? ?? '',
      name: user['name'] as String? ?? user['nickname'] as String? ?? '',
    );
  }
}

/// 单条歌词（LRC 文本）。
class FnLyric {
  const FnLyric({
    required this.guid,
    required this.content,
    this.isLRC = true,
    this.offset,
  });

  final String guid;
  final String content;
  final bool isLRC;
  final int? offset;

  factory FnLyric.fromJson(Map<String, Object?> json) {
    return FnLyric(
      guid: json['guid'] as String? ?? '',
      content: json['content'] as String? ?? '',
      isLRC: json['isLRC'] as bool? ?? true,
      offset: (json['offset'] as num?)?.toInt(),
    );
  }
}

/// 歌词列表响应（data 字段内为 {list, preferred}）。
class FnLyricResponse {
  const FnLyricResponse({required this.list, this.preferred});

  final List<FnLyric> list;
  final String? preferred;

  factory FnLyricResponse.fromJson(Map<String, Object?> json) {
    return FnLyricResponse(
      list: (json['list'] as List<Object?>?)
              ?.map((e) => FnLyric.fromJson(_asMap(e)))
              .toList() ??
          const <FnLyric>[],
      preferred: json['preferred'] as String?,
    );
  }

  static Map<String, Object?> _asMap(Object? data) {
    if (data is Map<Object?, Object?>) {
      return data.cast<String, Object?>();
    }
    return const <String, Object?>{};
  }
}

/// 顶层工具：把 Object? 安全转为 `Map<String, Object?>`（空则返回空 Map）。
Map<String, Object?> _asMap(Object? data) {
  if (data is Map<Object?, Object?>) {
    return data.cast<String, Object?>();
  }
  return const <String, Object?>{};
}
