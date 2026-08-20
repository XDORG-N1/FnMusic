import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 安全码验证服务（单例）
///
/// 对应服务器 `/access_code_verify` 端点：
/// - GET 返回 **204** → 无需安全码（服务器未开启访问码防护）；
/// - GET 返回 **401 / 403 / 429** → 需要且校验失败（访问码错误）；
/// - 其余非 2xx → 网络异常（由调用方按「暂不要求安全码」处理）。
///
/// 与网页版一致：请求头 `x-access-code: base64(安全码)`、`x-access-source: app`。
class AccessCodeService {
  AccessCodeService._();

  static final AccessCodeService instance = AccessCodeService._();

  static const String _verifyPath = '/access_code_verify';

  /// 独立 Dio 实例：不携带音乐 token、不注入自动重连拦截器，
  /// 仅用于安全码验证握手。
  Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      followRedirects: false,
      maxRedirects: 0,
      validateStatus: (_) => true,
    ),
  );

  @visibleForTesting
  void setDioForTest(Dio dio) => _dio = dio;

  /// 是否需要安全码：请求验证端点，返回 401 即需要。
  ///
  /// [isRelay] 为 true 时携带 `Cookie: mode=relay`（中继链路下服务器才识别该
  /// 请求，否则会 302 跳走拿不到验证结果）。
  ///
  /// 返回 true=需要安全码，false=不需要（204）。
  /// 网络异常抛 [DioException]，由调用方按「暂不要求」处理。
  Future<bool> requiresAccessCode(String baseUrl, {bool isRelay = false}) async {
    final Uri uri = Uri.parse('$baseUrl$_verifyPath');
    final Response<dynamic> response = await _dio.getUri(
      uri,
      options: Options(
        headers: isRelay ? const {'Cookie': 'mode=relay'} : null,
      ),
    );
    final int status = response.statusCode ?? 0;
    if (kDebugMode) {
      debugPrint('[AccessCode] verify probe → $status ($uri)');
    }
    return status == 401;
  }

  /// 校验安全码是否有效。
  ///
  /// [isRelay] 为 true 时携带 `Cookie: mode=relay`。
  ///
  /// 返回 true=有效（204），false=无效（401/403/429，访问码错误）。
  /// 网络异常抛 [DioException]，由调用方提示「网络异常」。
  Future<bool> verify(String baseUrl, String code, {bool isRelay = false}) async {
    final Uri uri = Uri.parse('$baseUrl$_verifyPath');
    final Response<dynamic> response = await _dio.getUri(
      uri,
      options: Options(
        headers: {
          if (isRelay) 'Cookie': 'mode=relay',
          'x-access-code': base64.encode(utf8.encode(code)),
          'x-access-source': 'app',
        },
      ),
    );
    final int status = response.statusCode ?? 0;
    if (kDebugMode) {
      debugPrint('[AccessCode] verify → $status ($uri)');
    }
    return status >= 200 && status < 300;
  }
}
