import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';

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
      'pageSize': 5,
    });
    final ApiPage<FnTrack> page = ApiPage<FnTrack>.fromJson(
      (data as Map<Object?, Object?>).cast<String, Object?>(),
      (Object? item) => FnTrack.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
    );
    expect(page.list, isNotEmpty);
    expect(page.list.first.guid, isNotEmpty);
  });
}
