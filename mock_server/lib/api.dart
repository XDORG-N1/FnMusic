import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fixtures.dart';
import 'png.dart';
import 'store.dart';
import 'wav.dart';

/// FNOS 音乐 API 契约（开发用 Mock）。
///
/// 所有端点挂在 `/music/api/v1` 下，与真实飞牛 NAS 布局一致，
/// 客户端可将 baseUrl 直接指向本服务器。
Handler buildApiHandler() {
  final Router router = Router()
    ..get('/health', _health)
    ..get('/static/cover', _cover)
    ..post('/user/password-login', _login)
    ..get('/track/list', _trackList)
    ..get('/track/detail', _trackDetail)
    ..get('/track/stream', _trackStream)
    ..post('/track/transcode', _transcode)
    ..post('/track/transcode/quit', _transcodeQuit)
    ..get('/transcode/<guid>/index.m3u8', _transcodePlaylist)
    ..get('/track/album-detail/list', _albumTracks)
    ..get('/track/artist-detail/list', _artistTracks)
    ..get('/track/genre-detail/list', _genreTracks)
    ..get('/track/playlist-detail/list', _playlistTracks)
    ..get('/track/roam-start', _roamStart)
    ..get('/track/roam-next', _roamNext)
    ..get('/album/list', _albumList)
    ..get('/artist/list', _artistList)
    ..get('/genre/list', _genreList)
    ..get('/playlist/list', _playlistList)
    ..post('/playlist/create', _playlistCreate)
    ..post('/playlist/delete', _playlistDelete)
    ..post('/playlist/edit', _playlistEdit)
    ..post('/playlist/add-track', _playlistAddTrack)
    ..post('/playlist/remove-track', _playlistRemoveTrack)
    ..get('/lyric/list', _lyricList)
    ..get('/favorite-track/list', _favoriteList)
    ..post('/favorite-track/create', _favoriteCreate)
    ..post('/favorite-track/delete', _favoriteDelete)
    ..get('/play-history/list', _historyList)
    ..post('/play-history/delete', _historyDelete)
    ..post('/event/report', _eventReport)
    ..get('/search/track', _searchTrack)
    ..get('/search/album', _searchAlbum)
    ..get('/search/artist', _searchArtist);

  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_authMiddleware())
      .addHandler(router.call);
}

// ---------- 通用 ----------

Response _json(Object? data, {String message = 'ok', int code = 0}) {
  // 与真实 FNOS 对齐：业务字段为 `msg`（非 `message`）。
  return Response.ok(
    jsonEncode(<String, Object?>{'code': code, 'msg': message, 'data': data}),
    headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
  );
}

Response _err(int code, String message) => _json(null, message: message, code: code);

String? _tokenFromRequest(Request req) {
  final String cookie = req.headers['cookie'] ?? '';
  final RegExpMatch? match = RegExp('music-token=([^;]+)').firstMatch(cookie);
  return match?.group(1);
}

bool _tokenValid(Request req) {
  final String? token = _tokenFromRequest(req);
  return token != null && token.isNotEmpty;
}

/// 鉴权中间件：除登录与健康检查外，要求 Cookie 携带 music-token。
Middleware _authMiddleware() {
  return (Handler inner) {
    return (Request req) async {
      // shelf_router mount 剥离前缀后路径无前导斜杠（如 "health"），此处规范化。
      final String rawPath = req.url.path;
      final String path = rawPath.startsWith('/') ? rawPath : '/$rawPath';
      final bool isPublic = path.endsWith('/user/password-login') ||
          path.endsWith('/health');
      if (!isPublic && !_tokenValid(req)) {
        return _err(401, '未登录');
      }
      return inner(req);
    };
  };
}

Future<Map<String, Object?>> _jsonBody(Request req) async {
  final String body = await req.readAsString();
  if (body.isEmpty) return <String, Object?>{};
  return (jsonDecode(body) as Map<Object?, Object?>).cast<String, Object?>();
}

// ---------- 健康 / 登录 ----------

Response _health(Request req) => _json(<String, Object?>{'status': 'up'});

Response _cover(Request req) {
  final String coverId = req.url.queryParameters['coverId'] ?? 'default';
  final Uint8List png = solidPng(300, 300, coverId);
  return Response.ok(
    png,
    headers: <String, String>{
      'content-type': 'image/png',
      'content-length': png.length.toString(),
      'cache-control': 'max-age=86400',
    },
  );
}

Future<Response> _login(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  // 真实 FNOS 字段为 username；兼容旧契约的 user。
  final String? user = (body['username'] as String?) ?? (body['user'] as String?);
  final String? password = body['password'] as String?; // 已是 SHA-256
  if (user == null || user.isEmpty || password == null || password.isEmpty) {
    return _err(400, '缺少用户名或密码');
  }
  final String digest = sha256.convert(utf8.encode(user)).toString();
  final String token = 'mock-token-${sha256.convert(utf8.encode('$user|$digest')).toString().substring(0, 16)}';
  return _json(<String, Object?>{
    // 与真实 FNOS 对齐：data.userToken + data.user.guid / name。
    'userToken': token,
    'user': <String, Object?>{
      'guid': user,
      'userId': user,
      'name': user,
      'nickname': user,
    },
  });
}

// ---------- 目录 ----------

int _page(Map<String, Object?> query) => int.tryParse(query['page']?.toString() ?? '') ?? 1;
int _pageSize(Map<String, Object?> query) =>
    (int.tryParse(query['size']?.toString() ?? '') ?? 100).clamp(1, 500);
List<T> _paginate<T>(List<T> items, int page, int pageSize) {
  final int start = (page - 1) * pageSize;
  if (start >= items.length) return <T>[];
  return items.sublist(start, (start + pageSize).clamp(0, items.length));
}

Map<String, Object?> _pageWrap(List<Object?> list, int total, int page, int pageSize) {
  return <String, Object?>{
    'list': list,
    'total': total,
    'page': page,
    'pageSize': pageSize,
  };
}

Response _trackList(Request req) {
  final Map<String, Object?> query = req.url.queryParameters;
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> list = _paginate(tracks, page, pageSize)
      .map((MockTrack t) => t.toJson())
      .toList();
  return _json(_pageWrap(list, tracks.length, page, pageSize));
}

Response _trackDetail(Request req) {
  final String? guid = req.url.queryParameters['guid'];
  final MockTrack? track = guid == null ? null : trackByGuid[guid];
  if (track == null) return _err(404, '曲目不存在');
  return _json(track.toJson());
}

Response _albumList(Request req) {
  final Map<String, Object?> query = req.url.queryParameters;
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> list = _paginate(albums, page, pageSize)
      .map((MockAlbum a) => <String, Object?>{
            'guid': a.guid,
            'name': a.name,
            'coverId': a.coverId,
            'year': a.year,
            'trackCount': tracks
                .where((MockTrack t) => t.albumGuid == a.guid)
                .length,
          })
      .toList();
  return _json(_pageWrap(list, albums.length, page, pageSize));
}

/// 详情页曲目列表公共逻辑：按 [match] 过滤 + 分页 + 100002/100005 对齐真实 FNOS。
///
/// 真实 FNOS 参数名为 `albumGUID`/`artistGUID`/`genreGUID`/`playlistGUID`
/// （非 `guid`），缺参返回 100002（InvalidArgs），空结果返回 `{list, total}`。
Response _detailTracks(Request req, String guidParam,
    bool Function(MockTrack t) match) {
  final Map<String, Object?> query = req.url.queryParameters;
  final String? guid = query[guidParam]?.toString();
  if (guid == null || guid.isEmpty) {
    return _err(100002, 'invalid arguments');
  }
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> all = tracks.where(match).map((MockTrack t) => t.toJson()).toList();
  final List<Object?> list = _paginate(all, page, pageSize);
  // 与真实 FNOS 一致：data 为分页包裹 {list, total}，缺 page/pageSize 字段。
  return _json(<String, Object?>{'list': list, 'total': all.length});
}

Response _albumTracks(Request req) {
  final String? guid = req.url.queryParameters['albumGUID'];
  return _detailTracks(req, 'albumGUID', (MockTrack t) => t.albumGuid == guid);
}

Response _artistList(Request req) {
  final Map<String, Object?> query = req.url.queryParameters;
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> list = _paginate(artists, page, pageSize)
      .map((MockArtist a) => <String, Object?>{
            'guid': a.guid,
            'name': a.name,
            'coverId': a.coverId,
          })
      .toList();
  return _json(_pageWrap(list, artists.length, page, pageSize));
}

Response _artistTracks(Request req) {
  final String? guid = req.url.queryParameters['artistGUID'];
  return _detailTracks(req, 'artistGUID', (MockTrack t) => t.artistGuids.contains(guid));
}

Response _genreList(Request req) {
  // 与真实 FNOS 一致：data 为分页包裹 {list, total}。
  final List<Object?> list = genres
      .map((MockGenre g) => <String, Object?>{'guid': g.guid, 'name': g.name})
      .toList();
  return _json(_pageWrap(list, list.length, 1, list.length));
}

Response _genreTracks(Request req) {
  final String? guid = req.url.queryParameters['genreGUID'];
  return _detailTracks(req, 'genreGUID', (MockTrack t) => t.genreGuids.contains(guid));
}

Response _playlistList(Request req) {
  // 与真实 FNOS 一致：data 为分页包裹 {list, total}。
  final List<MockPlaylist> all = MockStore.instance.playlists;
  final Map<String, Object?> query = req.url.queryParameters;
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> list = _paginate(all, page, pageSize)
      .map((MockPlaylist p) => <String, Object?>{
            'guid': p.guid,
            'name': p.name,
            'createdAt': p.createdAt,
            'trackCount': p.trackGuids.length,
          })
      .toList();
  return _json(_pageWrap(list, all.length, page, pageSize));
}

Response _playlistTracks(Request req) {
  final Map<String, Object?> query = req.url.queryParameters;
  final String? guid = query['playlistGUID']?.toString();
  if (guid == null || guid.isEmpty) return _err(100002, 'invalid arguments');
  final MockPlaylist? playlist = MockStore.instance.playlists
      .where((MockPlaylist p) => p.guid == guid)
      .firstOrNull;
  if (playlist == null) return _err(100005, '资源不存在或已被删除');
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> all = playlist.trackGuids
      .map((String g) => trackByGuid[g])
      .whereType<MockTrack>()
      .map((MockTrack t) => t.toJson())
      .toList();
  final List<Object?> list = _paginate(all, page, pageSize);
  // 与真实 FNOS 一致：data 为分页包裹 {list, total}，缺 page/pageSize 字段。
  return _json(<String, Object?>{'list': list, 'total': all.length});
}

Future<Response> _playlistCreate(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final String? name = body['name'] as String?;
  if (name == null || name.isEmpty) return _err(400, '缺少歌单名');
  final MockPlaylist playlist = MockStore.instance.createPlaylist(name);
  return _json(<String, Object?>{'guid': playlist.guid});
}

Future<Response> _playlistDelete(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  MockStore.instance.playlists.removeWhere(
      (MockPlaylist p) => p.guid == body['guid']?.toString());
  return _json(<String, Object?>{});
}

Future<Response> _playlistEdit(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final MockPlaylist? playlist = MockStore.instance.playlists
      .where((MockPlaylist p) => p.guid == body['guid']?.toString())
      .firstOrNull;
  if (playlist == null) return _err(404, '歌单不存在');
  final String? name = body['name'] as String?;
  if (name != null && name.isNotEmpty) playlist.name = name;
  return _json(<String, Object?>{});
}

Future<Response> _playlistAddTrack(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final MockPlaylist? playlist = MockStore.instance.playlists
      .where((MockPlaylist p) => p.guid == body['playlistGuid']?.toString())
      .firstOrNull;
  final String? trackGuid = body['trackGuid']?.toString();
  if (playlist == null || trackGuid == null) return _err(404, '歌单或曲目不存在');
  if (!playlist.trackGuids.contains(trackGuid)) {
    playlist.trackGuids.add(trackGuid);
  }
  return _json(<String, Object?>{});
}

Future<Response> _playlistRemoveTrack(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final MockPlaylist? playlist = MockStore.instance.playlists
      .where((MockPlaylist p) => p.guid == body['playlistGuid']?.toString())
      .firstOrNull;
  if (playlist == null) return _err(404, '歌单不存在');
  playlist.trackGuids.remove(body['trackGuid']?.toString());
  return _json(<String, Object?>{});
}

// ---------- 播放 ----------

final Uint8List _wavCache = generateWav();

Response _trackStream(Request req) {
  final String? guid = req.url.queryParameters['guid'];
  final MockTrack? track = guid == null ? null : trackByGuid[guid];
  if (track == null) return _err(404, '曲目不存在');
  return Response.ok(
    _wavCache,
    headers: <String, String>{
      'content-type': 'audio/wav',
      'content-length': _wavCache.length.toString(),
    },
  );
}

/// 转码：返回 base 相对播放列表地址（客户端拼到 API base 上播放）。
/// mp3 等无需转码的格式返回 400，与真实 FNOS 行为一致。
Future<Response> _transcode(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final String? guid = body['guid']?.toString();
  if (guid == null) return _err(400, '缺少 guid');
  final MockTrack? track = trackByGuid[guid];
  if (track == null) return _err(404, '曲目不存在');
  if (track.format == 'mp3') return _err(400, '该格式无需转码');
  return _json(<String, Object?>{
    'url': 'transcode/$guid/index.m3u8',
    'playlist': _hlsFor(track, req),
  });
}

Response _transcodeQuit(Request req) => _json(<String, Object?>{});

/// 提供转码后的 HLS 播放列表。段用绝对地址（任何解析方式都能拉流）。
Response _transcodePlaylist(Request req, String guid) {
  final MockTrack? track = trackByGuid[guid];
  if (track == null) return _err(404, '曲目不存在');
  return Response.ok(
    _hlsFor(track, req),
    headers: <String, String>{'content-type': 'application/vnd.apple.mpegurl'},
  );
}

/// 构造 HLS m3u8：段指向本服务 `track/stream`。
String _hlsFor(MockTrack track, Request req) {
  final String base = '${req.requestedUri.scheme}://${req.requestedUri.authority}'
      '/music/api/v1';
  return '#EXTM3U\n'
      '#EXT-X-VERSION:3\n'
      '#EXT-X-TARGETDURATION:10\n'
      '#EXT-X-PLAYLIST-TYPE:VOD\n'
      '#EXTINF:${track.duration / 1000},\n'
      '$base/track/stream?guid=${track.guid}\n'
      '#EXT-X-ENDLIST\n';
}

// ---------- 漫游（随机播放）----------

/// 推进 deviceId 的漫游游标并返回下一首 + 会话 roamId。
(MockTrack, String) _nextRoamTrack(String deviceId) {
  final MockStore store = MockStore.instance;
  final int cursor = store.roamCursor[deviceId] ?? 0;
  final MockTrack next = tracks[cursor % tracks.length];
  store.roamCursor[deviceId] = cursor + 1;
  // 与真实 FNOS 一致：roamId 标识同一条漫游链。
  final String roamId = 'roam_${deviceId}_${cursor}_'
      '${sha256.convert(utf8.encode('$deviceId|$cursor')).toString().substring(0, 8)}';
  return (next, roamId);
}

Map<String, Object?> _roamTrackJson(MockTrack track, String roamId) =>
    <String, Object?>{'roamId': roamId, 'track': track.toJson()};

Response _roamStart(Request req) {
  final String deviceId = req.url.queryParameters['deviceId'] ?? 'unknown';
  final (MockTrack track, String roamId) = _nextRoamTrack(deviceId);
  // 真实 FNOS：data.current 必填（roamId + track），next 可选。
  return _json(<String, Object?>{
    'current': _roamTrackJson(track, roamId),
    'next': null,
  });
}

Response _roamNext(Request req) {
  final String deviceId = req.url.queryParameters['deviceId'] ?? 'unknown';
  final (MockTrack track, String roamId) = _nextRoamTrack(deviceId);
  // 真实 FNOS：data.next（roamId + track）；previous/current 可缺省。
  return _json(<String, Object?>{
    'previous': null,
    'current': null,
    'next': _roamTrackJson(track, roamId),
  });
}

// ---------- 歌词 ----------

Response _lyricList(Request req) {
  final String? guid = req.url.queryParameters['trackGUID'];
  if (guid == null) return _err(400, '缺少 trackGUID');
  if (!trackByGuid.containsKey(guid)) return _err(404, '曲目不存在');
  final String? lrc = lyricsByTrack[guid];
  if (lrc == null) return _json(<Object?>[]);
  return _json(<Object?>[
    <String, Object?>{
      'guid': 'lyr_$guid',
      'trackGUID': guid,
      'content': lrc,
      'format': 'lrc',
      'preferred': true,
    },
  ]);
}

// ---------- 收藏 ----------

Response _favoriteList(Request req) {
  // 与真实 FNOS 一致：data 为分页包裹 {list, total}。
  final MockStore store = MockStore.instance;
  final List<Object?> all = store.favoriteTrackGuids
      .map((String g) => trackByGuid[g])
      .whereType<MockTrack>()
      .map((MockTrack t) => t.toJson())
      .toList();
  final Map<String, Object?> query = req.url.queryParameters;
  final int page = _page(query);
  final int pageSize = _pageSize(query);
  final List<Object?> list = _paginate(all, page, pageSize);
  return _json(_pageWrap(list, all.length, page, pageSize));
}

Future<Response> _favoriteCreate(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final String? guid = body['trackGuid']?.toString();
  if (guid == null || !trackByGuid.containsKey(guid)) return _err(404, '曲目不存在');
  MockStore.instance.favoriteTrackGuids.add(guid);
  return _json(<String, Object?>{});
}

Future<Response> _favoriteDelete(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  MockStore.instance.favoriteTrackGuids.remove(body['trackGuid']?.toString());
  return _json(<String, Object?>{});
}

// ---------- 历史 ----------

Response _historyList(Request req) {
  return _json(MockStore.instance.playHistory);
}

Future<Response> _historyDelete(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  final String? guid = body['trackGuid']?.toString();
  if (guid != null) {
    MockStore.instance.playHistory
        .removeWhere((Map<String, Object?> e) => e['trackGuid'] == guid);
  } else {
    MockStore.instance.playHistory.clear();
  }
  return _json(<String, Object?>{});
}

Future<Response> _eventReport(Request req) async {
  final Map<String, Object?> body = await _jsonBody(req);
  if (body['eventType'] == 'track_play') {
    final Map<String, Object?> track = (body['data'] as Map<Object?, Object?>? ?? <Object?, Object?>{})
        .cast<String, Object?>();
    MockStore.instance.playHistory.insert(
      0,
      <String, Object?>{
        'trackGuid': track['trackGuid'],
        'playedAt': DateTime.now().millisecondsSinceEpoch,
        'durationMs': track['durationMs'],
      },
    );
  }
  return _json(<String, Object?>{});
}

// ---------- 搜索 ----------

/// 搜索接口与真实 FNOS 一致：`data` 为分页结构 `{list, total}`（非裸数组）。
Response _searchTrack(Request req) {
  final String q = req.url.queryParameters['q'] ?? '';
  final List<Object?> list = tracks
      .where((MockTrack t) =>
          t.title.contains(q) ||
          t.artistGuids.any((String g) => artistByGuid[g]!.name.contains(q)))
      .map((MockTrack t) => t.toJson())
      .toList();
  return _json(<String, Object?>{'list': list, 'total': list.length});
}

Response _searchAlbum(Request req) {
  final String q = req.url.queryParameters['q'] ?? '';
  final List<Object?> list = albums
      .where((MockAlbum a) => a.name.contains(q))
      .map((MockAlbum a) => <String, Object?>{
            'guid': a.guid,
            'name': a.name,
            'coverId': a.coverId,
            'year': a.year,
          })
      .toList();
  return _json(<String, Object?>{'list': list, 'total': list.length});
}

Response _searchArtist(Request req) {
  final String q = req.url.queryParameters['q'] ?? '';
  final List<Object?> list = artists
      .where((MockArtist a) => a.name.contains(q))
      .map((MockArtist a) => <String, Object?>{
            'guid': a.guid,
            'name': a.name,
            'coverId': a.coverId,
          })
      .toList();
  return _json(<String, Object?>{'list': list, 'total': list.length});
}
