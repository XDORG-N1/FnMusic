/// FNOS 音乐 API 数据模型。
///
/// 响应统一包装为 `{code, message, data}`，与 mock 服务器契约一致。
library;

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
      message: json['message'] as String? ?? '',
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
  const FnAlbum({required this.guid, required this.name, this.coverId, this.year});

  final String guid;
  final String name;
  final String? coverId;
  final int? year;

  factory FnAlbum.fromJson(Map<String, Object?> json) {
    return FnAlbum(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coverId: json['coverId'] as String?,
      year: (json['year'] as num?)?.toInt(),
    );
  }
}

/// 流派。
class FnGenre {
  const FnGenre({required this.guid, required this.name});

  final String guid;
  final String name;

  factory FnGenre.fromJson(Map<String, Object?> json) {
    return FnGenre(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
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
    this.createdAt,
    this.trackCount,
  });

  final String guid;
  final String name;
  final int? createdAt;
  final int? trackCount;

  factory FnPlaylist.fromJson(Map<String, Object?> json) {
    return FnPlaylist(
      guid: json['guid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt(),
      trackCount: (json['trackCount'] as num?)?.toInt(),
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
      token: data['token'] as String? ?? '',
      userId: user['userId'] as String? ?? '',
      name: user['nickname'] as String? ?? user['name'] as String? ?? '',
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
