import 'package:flutter/foundation.dart';

import 'account_entry.dart';
import 'account_store.dart';
import 'api_client.dart';
import 'api_models.dart';

/// 登录状态。
enum AuthStatus { loggedOut, connecting, loggedIn }

/// 认证服务：登录 / 登出 / 会话恢复。
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  final ValueNotifier<AuthStatus> status =
      ValueNotifier<AuthStatus>(AuthStatus.loggedOut);

  bool _initialized = false;

  /// 启动时恢复已保存账号的会话。
  Future<void> initialize() async {
    if (_initialized) return;
    await AccountStore.instance.ensureLoaded();
    final AccountEntry? account = AccountStore.instance.activeAccount;
    if (account != null && account.token != null && account.token!.isNotEmpty) {
      ApiClient.instance.setServerUrl(account.serverUrl);
      ApiClient.instance.setToken(account.token);
      status.value = AuthStatus.loggedIn;
    } else {
      status.value = AuthStatus.loggedOut;
    }
    _initialized = true;
  }

  /// 登录并保存账号。
  Future<AccountEntry> login({
    required String serverUrl,
    required String user,
    required String password,
    String? displayName,
  }) async {
    status.value = AuthStatus.connecting;
    try {
      ApiClient.instance.setServerUrl(serverUrl);
      final FnLoginResult result = await ApiClient.instance.login(
        user: user,
        password: password,
      );
      final AccountEntry entry = AccountEntry(
        id: '$serverUrl|$user',
        serverUrl: serverUrl,
        userName: user,
        displayName: displayName ?? result.name,
        token: result.token,
      );
      await AccountStore.instance.addAccount(entry);
      await AccountStore.instance.setActiveAccount(entry.id);
      status.value = AuthStatus.loggedIn;
      return entry;
    } catch (e) {
      status.value = AuthStatus.loggedOut;
      rethrow;
    }
  }

  /// 切换账号（使用已保存的 token）。
  Future<void> switchToAccount(AccountEntry account) async {
    await AccountStore.instance.setActiveAccount(account.id);
    if (account.token != null) {
      ApiClient.instance.setServerUrl(account.serverUrl);
      ApiClient.instance.setToken(account.token);
      status.value = AuthStatus.loggedIn;
    }
  }

  /// 登出。
  Future<void> logout() async {
    final AccountEntry? account = AccountStore.instance.activeAccount;
    if (account != null) {
      final AccountEntry updated = account.copyWith(token: null);
      await AccountStore.instance.addAccount(updated);
    }
    ApiClient.instance.setToken(null);
    status.value = AuthStatus.loggedOut;
  }
}
