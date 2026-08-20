import 'package:dio/dio.dart';

/// FN Connect 连接探测。
///
/// 完整版对接飞牛 `5ddd.com/api/v1/fn/con` 自动发现 NAS 地址；
/// 当前实现支持直接探测给定服务器根地址的可达性（连接回退基础）。
class FnConnectionProbeService {
  FnConnectionProbeService._();

  static final FnConnectionProbeService instance = FnConnectionProbeService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  /// 探测服务器根地址是否可达（检查 `/music/api/v1/health`）。
  /// 返回可达的服务器根地址（去掉尾斜杠）。
  Future<String?> probeServer(String serverRoot) async {
    final String root = serverRoot.trim().replaceAll(RegExp(r'/+$'), '');
    if (root.isEmpty) return null;
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$root/music/api/v1/health');
      if (resp.statusCode == 200) return root;
    } catch (_) {}
    return null;
  }

  /// 顺序探测多个候选地址，返回第一个可达的（连接回退）。
  Future<String?> probeServers(List<String> candidates) async {
    for (final String c in candidates) {
      final String? ok = await probeServer(c);
      if (ok != null) return ok;
    }
    return null;
  }
}
