import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/album_service.dart';
import 'package:fnmusic/app/services/feiniu/artist_service.dart';

/// 集成测试：依赖本机运行的 mock FNOS 服务器（端口 8818）。
/// 服务器未运行时自动跳过。
void main() {
  const String baseUrl = 'http://127.0.0.1:8818';

  Future<bool> serverUp() async {
    try {
      final Response<dynamic> resp =
          await Dio().get<dynamic>('$baseUrl/music/api/v1/health');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  test('登录并获取曲目列表（对接 mock 服务器）', () async {
    final bool up = await serverUp();
    if (!up) {
      markTestSkipped('mock 服务器未运行（dart run mock_server/bin/server.dart --port 8818）');
      return;
    }

    final ApiClient client = ApiClient.instance;
    client.setServerUrl(baseUrl);

    final FnLoginResult result = await client.login(user: 'admin', password: 'admin');
    expect(result.token, isNotEmpty);

    final dynamic data = await client.getData('/track/list', query: <String, Object?>{
      'page': 1,
      // 真实 FNOS 分页参数为 `size`。
      'size': 5,
    });
    final ApiPage<FnTrack> page = ApiPage<FnTrack>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      (Object? item) => FnTrack.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
    );
    expect(page.list, isNotEmpty);
    expect(page.list.first.guid, isNotEmpty);
  });

  test('专辑 / 歌手详情曲目：分页响应 `{list,total}` 解析不再 TypeError', () async {
    final bool up = await serverUp();
    if (!up) {
      markTestSkipped('mock 服务器未运行（dart run mock_server/bin/server.dart --port 8818）');
      return;
    }

    final ApiClient client = ApiClient.instance;
    client.setServerUrl(baseUrl);
    await client.login(user: 'admin', password: 'admin');

    // mock 已按真实 FNOS 对齐为分页包裹 `{list,total}`，旧实现按裸 List 强转会抛 TypeError。
    final List<FnTrack> albumTracks =
        await FnAlbumService.instance.fetchAlbumTracks('alb_001');
    expect(albumTracks, isNotEmpty);
    expect(albumTracks.first.guid, isNotEmpty);

    final List<FnTrack> artistTracks =
        await FnArtistService.instance.fetchArtistTracks('art_001');
    expect(artistTracks, isNotEmpty);
  });
}
