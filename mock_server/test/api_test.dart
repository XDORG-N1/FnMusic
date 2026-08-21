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
}
