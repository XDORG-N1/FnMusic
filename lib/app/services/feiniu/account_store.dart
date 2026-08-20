import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_entry.dart';

/// 多账号管理（持久化到 SharedPreferences）。
class AccountStore {
  AccountStore._();

  static final AccountStore instance = AccountStore._();

  static const String _prefsList = 'settings_accounts.list';
  static const String _prefsActive = 'settings_accounts.active';

  final ValueNotifier<List<AccountEntry>> accounts =
      ValueNotifier<List<AccountEntry>>(<AccountEntry>[]);
  final ValueNotifier<String?> activeAccountId =
      ValueNotifier<String?>(null);

  bool _loaded = false;

  /// 当前激活账号。
  AccountEntry? get activeAccount {
    final String? id = activeAccountId.value;
    if (id == null) return null;
    for (final AccountEntry a in accounts.value) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_prefsList) ?? const <String>[];
    accounts.value = raw
        .map(AccountEntry.decode)
        .whereType<AccountEntry>()
        .toList();
    activeAccountId.value = prefs.getString(_prefsActive);
    _loaded = true;
  }

  /// 新增账号；已存在同一身份（identityKey）则更新。
  Future<AccountEntry> addAccount(AccountEntry entry) async {
    final List<AccountEntry> list = List<AccountEntry>.from(accounts.value);
    final int index = list.indexWhere(
      (AccountEntry a) => a.identityKey == entry.identityKey,
    );
    if (index >= 0) {
      list[index] = entry;
    } else {
      list.add(entry);
    }
    accounts.value = list;
    if (activeAccountId.value == null) {
      await setActiveAccount(entry.id);
    }
    await _persist();
    return entry;
  }

  Future<void> removeAccount(String id) async {
    accounts.value =
        accounts.value.where((AccountEntry a) => a.id != id).toList();
    if (activeAccountId.value == id) {
      activeAccountId.value =
          accounts.value.isEmpty ? null : accounts.value.first.id;
    }
    await _persist();
  }

  Future<void> setActiveAccount(String? id) async {
    activeAccountId.value = id;
    await _persist();
    final AccountEntry? account = activeAccount;
    if (account != null) {
      // 同步到 ApiClient。
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsList,
      accounts.value.map((AccountEntry a) => a.encode()).toList(),
    );
    await prefs.setString(_prefsActive, activeAccountId.value ?? '');
  }

  /// 测试用：清空内存状态（SharedPreferences mock 由测试方重置）。
  @visibleForTesting
  void resetForTest() {
    _loaded = false;
    accounts.value = <AccountEntry>[];
    activeAccountId.value = null;
  }
}
