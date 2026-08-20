import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'package:fnmusic_mock_server/api.dart';

Future<void> main(List<String> args) async {
  final int port = _argInt(args, 'port', 8818);
  final InternetAddress address = _argHas(args, 'host')
      ? InternetAddress.anyIPv4
      : InternetAddress.loopbackIPv4;

  // API 挂在 /music/api/v1 下，与真实飞牛 NAS 布局一致。
  final Router topRouter = Router()
    ..mount('/music/api/v1/', buildApiHandler())
    ..get('/', (Request req) => Response.ok(
        'FnMusic Mock FNOS API Server v0.1\n'
        'API base: http://localhost:$port/music/api/v1\n'
        '登录示例: POST /music/api/v1/user/password-login {"user":"admin","password":"<sha256>"}\n'));

  final HttpServer server =
      await shelf_io.serve(topRouter.call, address, port);

  stdout.writeln('Mock FNOS API 服务器已启动: http://${server.address.host}:${server.port}');
  stdout.writeln('API base: http://${server.address.host}:${server.port}/music/api/v1');
  stdout.writeln('按 Ctrl+C 停止');
}

int _argInt(List<String> args, String name, int fallback) {
  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == '--$name') {
      return int.tryParse(args[i + 1]) ?? fallback;
    }
  }
  return fallback;
}

bool _argHas(List<String> args, String name) => args.contains('--$name');
