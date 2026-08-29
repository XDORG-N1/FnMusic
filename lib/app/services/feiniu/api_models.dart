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
