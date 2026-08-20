import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/feiniu/api_client.dart';

void main() {
  group('ApiClient.resolvePlayUrl', () {
    late ApiClient client;

    setUp(() {
      client = ApiClient.instance;
      client.setServerUrl('http://10.0.2.2:8818');
    });

    test('绝对地址原样返回', () {
      expect(
        client.resolvePlayUrl('https://nas.example.com/transcode/x.m3u8'),
        'https://nas.example.com/transcode/x.m3u8',
      );
      expect(
        client.resolvePlayUrl('http://127.0.0.1:8821/a/b.m3u8'),
        'http://127.0.0.1:8821/a/b.m3u8',
      );
    });

    test('相对地址拼到 API base 上', () {
      expect(
        client.resolvePlayUrl('transcode/trk_001/index.m3u8'),
        'http://10.0.2.2:8818/music/api/v1/transcode/trk_001/index.m3u8',
      );
    });

    test('null / 空串返回 null', () {
      expect(client.resolvePlayUrl(null), isNull);
      expect(client.resolvePlayUrl(''), isNull);
    });
  });
}
