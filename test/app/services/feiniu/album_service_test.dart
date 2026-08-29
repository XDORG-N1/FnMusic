import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/album_service.dart';

/// 专辑服务单元测试：不依赖 mock 服务器（走网络前本地拦截）。
void main() {
  setUp(() {
    FnAlbumService.fetchAlbumTracksOverride = null;
    FnAlbumService.fetchAlbumsOverride = null;
  });

  tearDown(() {
    FnAlbumService.fetchAlbumTracksOverride = null;
    FnAlbumService.fetchAlbumsOverride = null;
  });

  test('fetchAlbumTracks 空 guid 本地拦截，不发起网络请求', () async {
    // 服务器地址未设置（无网络可用）；守卫在发请求前抛出即证明被拦截。
    await expectLater(
      FnAlbumService.instance.fetchAlbumTracks(''),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.code, 'code', 100002)
          .having(
              (ApiException e) => e.message, 'message', contains('专辑标识缺失'))),
    );
  });

  test('fetchAlbumTracks 空白字符串同样拦截', () async {
    await expectLater(
      FnAlbumService.instance.fetchAlbumTracks('   '),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.code, 'code', 100002)),
    );
  });

  test('ApiException.friendlyMessage 映射 100002 且原始 message 优先', () {
    // 服务端不带 message → 用兜底映射（100002=InvalidArgs）。
    expect(const ApiException(100002, '').friendlyMessage,
        '参数不完整或格式不正确');
    // 服务端带 message → 优先展示 message。
    expect(const ApiException(100002, '专辑已失效').friendlyMessage, '专辑已失效');
    expect(const ApiException(100005, '').friendlyMessage, '资源不存在或已被删除');
    expect(const ApiException(120001, '').friendlyMessage, '登录状态已失效，请重新登录');
    expect(const ApiException(-1, '').friendlyMessage, '响应格式异常，请稍后重试');
    expect(const ApiException(99999, '').friendlyMessage, '请求失败（错误码 99999）');
  });
}
