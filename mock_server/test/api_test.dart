import 'dart:convert';
import 'dart:io';

import 'package:fnmusic_mock_server/api.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';

/// FNOS Mock API 契约测试：在本机起真实服务器 + HTTP 请求。
///
/// 覆盖播放链路：鉴权 → 转码（url + m3u8 播放列表）→ 漫游随机会话推进。
void main() {
  late HttpServer server;
  late String base;

  setUpAll(() async {
    // 与 bin/server.dart 一致：API 挂在 /music/api/v1 下。
    final Router top = Router()..mount('/music/api/v1/', buildApiHandler());
    server = await io.serve(top.call, '127.0.0.1', 0);
    base = 'http://127.0.0.1:${server.port}/music/api/v1';
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  /// 发起 HTTP 请求并返回 (状态码, JSON body)。
  Future<(int, Map<String, Object?>)> call(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req =
          await client.openUrl(method, Uri.parse('$base$path'));
      headers?.forEach((String k, String v) => req.headers.set(k, v));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final HttpClientResponse resp = await req.close();
      final String text = await utf8.decoder.bind(resp).join();
      final Map<String, Object?> json =
          text.isEmpty ? <String, Object?>{} : jsonDecode(text) as Map<String, Object?>;
      return (resp.statusCode, json);
    } finally {
      client.close(force: true);
    }
  }

  Map<String, Object?> dataOf((int, Map<String, Object?>) r) =>
      r.$2['data'] as Map<String, Object?>? ?? const <String, Object?>{};

  Map<String, String> auth(String token) =>
      <String, String>{'Cookie': 'music-token=$token'};

  Future<String> loginToken() async {
    final (int, Map<String, Object?>) r = await call(
      'POST',
      '/user/password-login',
      body: <String, Object?>{'user': 'admin', 'password': 'admin'},
    );
    expect(r.$1, 200);
    expect(r.$2['code'], 0);
    return dataOf(r)['userToken']! as String;
  }

  group('鉴权', () {
    test('未登录访问业务端点返回非 0 code', () async {
      final (int, Map<String, Object?>) r = await call('GET', '/track/list');
      expect(r.$2['code'], isNot(0));
    });

    test('登录后带 Cookie 访问成功', () async {
      final String token = await loginToken();
      final (int, Map<String, Object?>) r =
          await call('GET', '/track/list', headers: auth(token));
      expect(r.$2['code'], 0);
    });
  });

  group('转码', () {
    late String token;

    setUp(() async {
      token = await loginToken();
    });

    test('POST /track/transcode 返回 base 相对播放列表地址', () async {
      final (int, Map<String, Object?>) r = await call(
        'POST',
        '/track/transcode',
        headers: auth(token),
        body: <String, Object?>{'guid': 'trk_001'},
      );
      expect(r.$2['code'], 0);
      expect(dataOf(r)['url'], 'transcode/trk_001/index.m3u8');
    });

    test('GET /transcode/<guid>/index.m3u8 返回合法 HLS 播放列表', () async {
      final HttpClient client = HttpClient();
      try {
        final HttpClientRequest req = await client.getUrl(
          Uri.parse('$base/transcode/trk_001/index.m3u8'),
        );
        req.headers.set('Cookie', 'music-token=$token');
        final HttpClientResponse resp = await req.close();
        final String playlist = await utf8.decoder.bind(resp).join();
        expect(resp.statusCode, 200);
        expect(playlist, contains('#EXTM3U'));
        expect(playlist, contains('#EXTINF:214.0,'));
        expect(playlist, contains('/music/api/v1/track/stream?guid=trk_001'));
      } finally {
        client.close(force: true);
      }
    });

    test('mp3 格式拒绝转码', () async {
      final (int, Map<String, Object?>) r = await call(
        'POST',
        '/track/transcode',
        headers: auth(token),
        body: <String, Object?>{'guid': 'trk_003'},
      );
      expect(r.$2['code'], isNot(0));
    });
  });

  group('文件夹选择器（app-center authed-dir）', () {
    test('授权目录根 + 子目录：顶层仅返回根，parent 只返回直接子目录', () async {
      final String token = await loginToken();

      final (int, Map<String, Object?>) roots =
          await call('GET', '/app-center/authed-dir/list', headers: auth(token));
      expect(roots.$2['code'], 0);
      final List<Object?> rootList =
          (dataOf(roots)['list']! as List<Object?>).cast<Object?>();
      // 顶层只有根路径（/vol1、/vol00…），不含子目录。
      expect(rootList, isNotEmpty);
      for (final Object? item in rootList) {
        final Map<String, Object?> dir =
            (item! as Map<Object?, Object?>).cast<String, Object?>();
        // 顶层根路径只有一段（/vol1、/vol00…）。
        expect(dir['path']!.toString().split('/').where((String s) => s.isNotEmpty).length, 1);
        expect(dir['name'], isNotEmpty);
      }

      // parent=/vol1 → 直接子目录（media/downloads/1000/@appshare），不含 Music 等深层。
      final (int, Map<String, Object?>) sub = await call(
        'GET',
        '/app-center/authed-dir/sub/list?parent=/vol1',
        headers: auth(token),
      );
      expect(sub.$2['code'], 0);
      final List<Object?> subList =
          (dataOf(sub)['list']! as List<Object?>).cast<Object?>();
      expect(subList, isNotEmpty);
      for (final Object? item in subList) {
        final Map<String, Object?> dir =
            (item! as Map<Object?, Object?>).cast<String, Object?>();
        expect(dir['path'], startsWith('/vol1/'));
        expect(dir['path']!.toString().split('/').length, 3);
      }

      // 缺 parent → 100002。
      final (int, Map<String, Object?>) bad = await call(
        'GET',
        '/app-center/authed-dir/sub/list',
        headers: auth(token),
      );
      expect(bad.$2['code'], 100002);
    });
  });

  group('漫游随机播放', () {
    Map<String, Object?> currentOf(Map<String, Object?> r) =>
        (r['current'] as Map<Object?, Object?>).cast<String, Object?>();

    Map<String, Object?> nextOf(Map<String, Object?> r) =>
        (r['next'] as Map<Object?, Object?>).cast<String, Object?>();

    test('会话按 deviceId 推进且曲目不重复', () async {
      final String token = await loginToken();

      final (int, Map<String, Object?>) start =
          await call('GET', '/track/roam-start?deviceId=dev-1', headers: auth(token));
      final Map<String, Object?> current = currentOf(dataOf(start));
      expect(current['roamId'], isNotEmpty);
      final Map<String, Object?> firstTrack =
          current['track']! as Map<String, Object?>;
      final String firstGuid = firstTrack['guid']! as String;
      final String firstRoamId = current['roamId']! as String;

      final (int, Map<String, Object?>) next = await call(
        'GET',
        '/track/roam-next?deviceId=dev-1&relativeRoamId=$firstRoamId',
        headers: auth(token),
      );
      final Map<String, Object?> nextTrack =
          nextOf(dataOf(next))['track']! as Map<String, Object?>;
      expect(nextTrack['guid'], isNot(firstGuid));
    });

    test('不同 deviceId 有独立游标', () async {
      final String token = await loginToken();

      final (int, Map<String, Object?>) a1 = await call(
        'GET',
        '/track/roam-start?deviceId=dev-a',
        headers: auth(token),
      );
      final (int, Map<String, Object?>) a2 = await call(
        'GET',
        '/track/roam-start?deviceId=dev-a',
        headers: auth(token),
      );
      final (int, Map<String, Object?>) b1 = await call(
        'GET',
        '/track/roam-start?deviceId=dev-b',
        headers: auth(token),
      );
      // dev-a 已推进到第二首；dev-b 独立从第一首开始（两条会话互不影响）。
      expect(currentOf(dataOf(a2))['track'], isNot(currentOf(dataOf(a1))['track']));
      expect(currentOf(dataOf(b1))['track'], currentOf(dataOf(a1))['track']);
    });
  });

  group('歌单', () {
    late String token;

    setUp(() async {
      token = await loginToken();
    });

    test('创建 → 加入曲目 → 详情含曲目 → 移除后剩 1 首', () async {
      // 创建歌单。
      final (int, Map<String, Object?>) created = await call(
        'POST',
        '/playlist/create',
        headers: auth(token),
        body: <String, Object?>{'name': '测试歌单'},
      );
      expect(created.$2['code'], 0);
      final String guid = dataOf(created)['guid']! as String;
      expect(guid, isNotEmpty);

      // 加入两首曲目（trackGUIDs 数组）。
      final (int, Map<String, Object?>) added = await call(
        'POST',
        '/playlist/add-track',
        headers: auth(token),
        body: <String, Object?>{
          'guid': guid,
          'trackGUIDs': <String>['trk_001', 'trk_002'],
        },
      );
      expect(added.$2['code'], 0);

      // 歌单详情返回两首（{list, total}）。
      final (int, Map<String, Object?>) detail = await call(
        'GET',
        '/track/playlist-detail/list?playlistGUID=$guid&page=1&size=100',
        headers: auth(token),
      );
      expect(detail.$2['code'], 0);
      final Map<String, Object?> detailData = dataOf(detail);
      expect((detailData['list']! as List<Object?>).length, 2);
      expect(detailData['total'], 2);

      // 歌单列表 trackCount 正确。
      final (int, Map<String, Object?>) all = await call(
        'GET',
        '/playlist/list',
        headers: auth(token),
      );
      final Map<String, Object?> mine = (dataOf(all)['list']! as List<Object?>)
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> m) => m.cast<String, Object?>())
          .firstWhere((Map<String, Object?> p) => p['guid'] == guid);
      expect(mine['name'], '测试歌单');
      expect(mine['trackCount'], 2);

      // 移除一首 → 剩一首。
      final (int, Map<String, Object?>) removed = await call(
        'POST',
        '/playlist/remove-track',
        headers: auth(token),
        body: <String, Object?>{
          'guid': guid,
          'trackGUIDs': <String>['trk_001'],
        },
      );
      expect(removed.$2['code'], 0);

      final (int, Map<String, Object?>) after = await call(
        'GET',
        '/track/playlist-detail/list?playlistGUID=$guid&page=1&size=100',
        headers: auth(token),
      );
      expect(dataOf(after)['total'], 1);
    });

    test('缺 trackGUIDs → 400', () async {
      final (int, Map<String, Object?>) created = await call(
        'POST',
        '/playlist/create',
        headers: auth(token),
        body: <String, Object?>{'name': '空歌单'},
      );
      final String guid = dataOf(created)['guid']! as String;

      final (int, Map<String, Object?>) bad = await call(
        'POST',
        '/playlist/add-track',
        headers: auth(token),
        body: <String, Object?>{'guid': guid},
      );
      // 与真实 FNOS 一致：HTTP 200，业务错误码在 body.code。
      expect(bad.$1, 200);
      expect(bad.$2['code'], 400);
    });

    test('移除不在歌单中的曲目不报错', () async {
      final (int, Map<String, Object?>) created = await call(
        'POST',
        '/playlist/create',
        headers: auth(token),
        body: <String, Object?>{'name': '测试歌单2'},
      );
      final String guid = dataOf(created)['guid']! as String;

      final (int, Map<String, Object?>) removed = await call(
        'POST',
        '/playlist/remove-track',
        headers: auth(token),
        body: <String, Object?>{
          'guid': guid,
          'trackGUIDs': <String>['trk_999'],
        },
      );
      expect(removed.$2['code'], 0);
    });
  });
}
