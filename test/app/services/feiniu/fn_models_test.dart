import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/feiniu/fn_models.dart';

void main() {
  group('buildProbeCandidateSpecs', () {
    const params = FnConnectionParams(
      internalIPv4s: ['192.168.1.100'],
      publicIPv4s: ['120.239.1.2'],
      publicIPv6s: ['2409:8a55:1::2'],
      httpsPort: 5667,
      httpPort: 5666,
      relayAddresses: ['fnabc123.5ddd.com:443'],
    );

    test('默认顺序：内网→公网IPv6→公网IPv4→中继，IP 先 HTTP 后 HTTPS', () {
      final specs = buildProbeCandidateSpecs(
        fnId: 'fnabc123',
        params: params,
        order: kDefaultConnectionOrder,
      );
      final addresses = specs.map((s) => s.address).toList();

      // 内网 IP：HTTP 优先，HTTPS 兜底
      expect(addresses[0], 'http://192.168.1.100:5666');
      expect(addresses[1], 'https://192.168.1.100:5667');
      // 公网 IPv6 用方括号括起
      expect(addresses[2], 'http://[2409:8a55:1::2]:5666');
      expect(addresses[3], 'https://[2409:8a55:1::2]:5667');
      // 公网 IPv4
      expect(addresses[4], 'http://120.239.1.2:5666');
      expect(addresses[5], 'https://120.239.1.2:5667');
      // 中继：仅 HTTPS，域名去掉端口
      expect(addresses[6], 'https://fnabc123.5ddd.com');
      expect(specs[6].relayMode, isTrue);
      expect(specs[6].group, ProbeCandidateGroup.relay);
    });

    test('中继组地址为空时回退 fnId.5ddd.com 兜底', () {
      final specs = buildProbeCandidateSpecs(
        fnId: 'fnabc123',
        params: const FnConnectionParams(
          internalIPv4s: [],
          publicIPv4s: [],
          publicIPv6s: [],
          httpsPort: 5667,
          httpPort: 5666,
          relayAddresses: [],
        ),
        order: const [ProbeCandidateGroup.relay],
      );
      expect(specs.single.address, 'https://fnabc123.5ddd.com');
    });

    test('自定义顺序生效且空分组不贡献候选', () {
      final specs = buildProbeCandidateSpecs(
        fnId: 'fnabc123',
        params: const FnConnectionParams(
          internalIPv4s: ['192.168.1.100'],
          publicIPv4s: [],
          publicIPv6s: [],
          httpsPort: 5667,
          httpPort: 5666,
          relayAddresses: ['fnabc123.5ddd.com:443'],
        ),
        order: const [
          ProbeCandidateGroup.publicIPv6, // 无地址 → 不贡献
          ProbeCandidateGroup.relay,
          ProbeCandidateGroup.internal,
        ],
      );
      final addresses = specs.map((s) => s.address).toList();
      expect(addresses[0], 'https://fnabc123.5ddd.com');
      expect(addresses[1], 'http://192.168.1.100:5666');
    });

    test('分组标题中文', () {
      expect(ProbeCandidateGroup.internal.title, '内网');
      expect(ProbeCandidateGroup.publicIPv6.title, '公网 IPv6');
      expect(ProbeCandidateGroup.publicIPv4.title, '公网 IPv4');
      expect(ProbeCandidateGroup.relay.title, '中继');
    });

    test('FnConnectionResponse.fromJson 解析端口与地址列表', () {
      final resp = FnConnectionResponse.fromJson(const <String, dynamic>{
        'code': 0,
        'msg': 'ok',
        'data': <String, dynamic>{
          'ipv4': ['192.168.1.100'],
          'publicIpv4': ['120.239.1.2'],
          'publicIpv6': <String>[],
          'port': <String, dynamic>{'httpPort': 5666, 'httpsPort': 5667},
          'fn': ['fnabc123.5ddd.com:443'],
        },
      });
      expect(resp.isSuccess, isTrue);
      final params = resp.data!;
      expect(params.internalIPv4s, ['192.168.1.100']);
      expect(params.publicIPv4s, ['120.239.1.2']);
      expect(params.httpsPort, 5667);
      expect(params.httpPort, 5666);
      expect(params.relayAddresses, ['fnabc123.5ddd.com:443']);
    });

    test('FnConnectionResponse 失败态', () {
      final resp = FnConnectionResponse.fromJson(
        const <String, dynamic>{'code': 1, 'msg': 'FNID 无效'},
      );
      expect(resp.isSuccess, isFalse);
      expect(resp.data, isNull);
    });
  });
}
