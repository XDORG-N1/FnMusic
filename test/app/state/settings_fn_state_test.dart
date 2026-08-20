import 'package:fnmusic/app/services/feiniu/fn_models.dart';
import 'package:fnmusic/app/state/settings_fn_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AppFnConnectionSettings.resetForTest();
  });

  group('AppFnConnectionSettings', () {
    test('默认连接顺序为内网→公网IPv6→公网IPv4→中继', () async {
      await AppFnConnectionSettings.ensureLoaded();
      expect(
        AppFnConnectionSettings.connectionOrder.value,
        kDefaultConnectionOrder,
      );
    });

    test('持久化的连接顺序被加载（去重 + 补全缺失分组）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'fn_connection_order': <String>[
          ProbeCandidateGroup.relay.name,
          ProbeCandidateGroup.relay.name, // 重复
          ProbeCandidateGroup.publicIPv4.name,
        ],
      });
      await AppFnConnectionSettings.ensureLoaded();
      final order = AppFnConnectionSettings.connectionOrder.value;
      expect(order.first, ProbeCandidateGroup.relay);
      expect(order[1], ProbeCandidateGroup.publicIPv4);
      // 缺失的默认分组自动补全
      expect(order, containsAll(kDefaultConnectionOrder));
      expect(order.toSet().length, order.length);
    });

    test('禁用分组持久化并生效', () async {
      await AppFnConnectionSettings.ensureLoaded();
      await AppFnConnectionSettings.setGroupDisabled(
        ProbeCandidateGroup.relay,
        true,
      );
      expect(
        AppFnConnectionSettings.disabledGroups.value,
        contains(ProbeCandidateGroup.relay),
      );
      // 再次加载保留禁用状态
      AppFnConnectionSettings.resetForTest();
      await AppFnConnectionSettings.ensureLoaded();
      expect(
        AppFnConnectionSettings.disabledGroups.value,
        contains(ProbeCandidateGroup.relay),
      );
    });

    test('saveProbeResult 后 cachedConnection 返回缓存连接', () async {
      await AppFnConnectionSettings.ensureLoaded();
      await AppFnConnectionSettings.saveProbeResult(
        fnId: 'fnabc123',
        url: 'https://fnabc123.5ddd.com',
        method: 'HTTPS (fnabc123.5ddd.com)',
        isRelay: true,
      );
      expect(AppFnConnectionSettings.lastFnId, 'fnabc123');
      expect(AppFnConnectionSettings.lastIsRelay, isTrue);
      final cache = AppFnConnectionSettings.cachedConnection;
      expect(cache, isNotNull);
      expect(cache!.url, 'https://fnabc123.5ddd.com');
      expect(cache.isRelay, isTrue);
      expect(
        AppFnConnectionSettings.currentConnectionUrl.value,
        'https://fnabc123.5ddd.com',
      );
    });

    test('restoreConnection 无 fnId 时清除 lastFnId', () async {
      await AppFnConnectionSettings.ensureLoaded();
      await AppFnConnectionSettings.saveProbeResult(
        fnId: 'fnabc123',
        url: 'http://192.168.1.100:5666',
        method: 'HTTP (192.168.1.100:5666)',
      );
      await AppFnConnectionSettings.restoreConnection(
        url: 'http://10.0.2.2:8818',
        isRelay: false,
      );
      expect(AppFnConnectionSettings.lastFnId, isNull);
      final cache = AppFnConnectionSettings.cachedConnection;
      expect(cache!.url, 'http://10.0.2.2:8818');
      expect(cache.isRelay, isFalse);
    });

    test('安全码设置与清除', () async {
      await AppFnConnectionSettings.ensureLoaded();
      await AppFnConnectionSettings.setAccessCode('123456');
      expect(AppFnConnectionSettings.accessCode, '123456');
      await AppFnConnectionSettings.setAccessCode('  ');
      expect(AppFnConnectionSettings.accessCode, isNull);
    });

    test('clearConnection 清除连接信息但保留 lastFnId', () async {
      await AppFnConnectionSettings.ensureLoaded();
      await AppFnConnectionSettings.saveProbeResult(
        fnId: 'fnabc123',
        url: 'https://fnabc123.5ddd.com',
        method: 'HTTPS (fnabc123.5ddd.com)',
      );
      await AppFnConnectionSettings.clearConnection();
      expect(AppFnConnectionSettings.lastFnId, 'fnabc123');
      expect(AppFnConnectionSettings.cachedConnection, isNull);
      expect(AppFnConnectionSettings.accessCode, isNull);
    });
  });
}
