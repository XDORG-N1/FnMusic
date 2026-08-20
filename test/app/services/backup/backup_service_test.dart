import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/backup/backup_service.dart';
import 'package:fnmusic/app/services/feiniu/account_entry.dart';
import 'package:fnmusic/app/services/feiniu/account_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = AccountStore.instance;
  final backup = BackupService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store.resetForTest();
  });

  group('BackupSections', () {
    test('默认全选且 any 为真', () {
      const s = BackupSections();
      expect(s.accounts, isTrue);
      expect(s.stats, isTrue);
      expect(s.settings, isTrue);
      expect(s.any, isTrue);
    });

    test('copyWith 仅改动指定分块', () {
      const s = BackupSections();
      final s2 = s.copyWith(accounts: false);
      expect(s2.accounts, isFalse);
      expect(s2.stats, isTrue);
      expect(s2.settings, isTrue);
    });

    test('全部关闭时 any 为假', () {
      const s = BackupSections(accounts: false, stats: false, settings: false);
      expect(s.any, isFalse);
    });
  });

  group('BackupService', () {
    test('buildBackupJson 仅账号分块：结构正确、未选分块不导出', () async {
      await store.addAccount(const AccountEntry(
        id: 'a1',
        serverUrl: 'http://nas',
        userName: 'u',
        displayName: '用户',
        token: 't1',
      ));

      final jsonStr = await backup.buildBackupJson(
        const BackupSections(accounts: true, stats: false, settings: false),
      );
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(data['format'], BackupService.formatVersion);
      expect(data['app'], BackupService.appName);
      expect(data['dbVersion'], isNotNull);
      expect(data['sections'], isA<Map>());
      expect(data['accounts'], isA<List>());
      expect((data['accounts'] as List).length, 1);
      expect(data['currentAccountId'], 'a1');
      expect(data.containsKey('stats'), isFalse);
      expect(data.containsKey('settings'), isFalse);
    });

    test('buildBackupJson 仅设置分块：导出通用键、排除敏感键', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'settings_theme.mode': 'dark',
        'cache_limit_mb': 1024,
        // 敏感键：账号、运行时槽位、备份自身配置
        'settings_accounts.list': <String>['x'],
        'playback_state.wasPlaying': true,
        'backup_targets_v1': '[]',
      });

      final jsonStr = await backup.buildBackupJson(
        const BackupSections(accounts: false, stats: false, settings: true),
      );
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final settings = data['settings'] as Map<String, dynamic>;

      expect(settings.containsKey('settings_theme.mode'), isTrue);
      expect(settings.containsKey('cache_limit_mb'), isTrue);
      expect(settings.containsKey('settings_accounts.list'), isFalse);
      expect(settings.containsKey('playback_state.wasPlaying'), isFalse);
      expect(settings.containsKey('backup_targets_v1'), isFalse);
    });

    test('restoreFromJson：无效格式抛 FormatException', () {
      expect(
        backup.restoreFromJson('not-a-json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('restoreFromJson：非本应用备份抛 FormatException', () {
      expect(
        backup.restoreFromJson('{"format":1,"app":"other_music"}'),
        throwsA(isA<FormatException>()),
      );
    });

    test('restoreFromJson：账号分块还原并恢复当前账号', () async {
      await store.addAccount(const AccountEntry(
        id: 'a1',
        serverUrl: 'http://nas',
        userName: 'u',
        displayName: '用户',
        token: 't1',
      ));
      final jsonStr = await backup.buildBackupJson(
        const BackupSections(accounts: true, stats: false, settings: false),
      );

      store.resetForTest();
      final summary = await backup.restoreFromJson(jsonStr);

      expect(summary, contains('账号'));
      expect(store.accounts.value.length, 1);
      expect(store.accounts.value.first.id, 'a1');
      expect(store.activeAccountId.value, 'a1');
    });

    test('restoreFromJson：restrict 限制分块', () async {
      await store.addAccount(const AccountEntry(
        id: 'a1',
        serverUrl: 'http://nas',
        userName: 'u',
        displayName: '用户',
      ));
      // 同时导出账号与设置
      final jsonStr = await backup.buildBackupJson(
        const BackupSections(accounts: true, stats: false, settings: true),
      );

      store.resetForTest();
      final summary = await backup.restoreFromJson(
        jsonStr,
        restrict: const BackupSections(
          accounts: false,
          stats: false,
          settings: true,
        ),
      );

      expect(summary, isNot(contains('账号')));
      expect(summary, contains('应用设置'));
      expect(store.accounts.value, isEmpty);
    });
  });

  group('BackupTarget', () {
    test('toJson / fromJson 往返', () {
      final t = BackupTarget(
        id: 'x',
        name: '我的 NAS',
        endpoint: 'https://dav.example.com',
        username: 'u',
        password: 'p',
        path: '/dav',
      );
      final t2 = BackupTarget.fromJson(t.toJson());
      expect(t2.id, t.id);
      expect(t2.name, t.name);
      expect(t2.endpoint, t.endpoint);
      expect(t2.username, t.username);
      expect(t2.password, t.password);
      expect(t2.path, t.path);
    });

    test('fromJson 缺失字段取默认值', () {
      final t = BackupTarget.fromJson(<String, dynamic>{'endpoint': 'http://e'});
      expect(t.id, '');
      expect(t.path, BackupService.defaultBasePath);
    });
  });

  group('normalizeDir', () {
    test('空与空白归一到根目录', () {
      expect(BackupService.normalizeDir(''), '/');
      expect(BackupService.normalizeDir('   '), '/');
    });

    test('补前导斜杠', () {
      expect(BackupService.normalizeDir('a/b'), '/a/b');
    });

    test('去尾部斜杠与反斜杠转换', () {
      expect(BackupService.normalizeDir('/a/b/'), '/a/b');
      expect(BackupService.normalizeDir('a\\b'), '/a/b');
    });

    test('根目录保持', () {
      expect(BackupService.normalizeDir('/'), '/');
    });
  });
}
