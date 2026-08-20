import 'package:flutter/material.dart';

import '../../app/services/feiniu/account_entry.dart';
import '../../app/services/feiniu/account_store.dart';
import '../../app/services/feiniu/api_client.dart';
import '../../app/services/feiniu/auth_service.dart';

/// 登录页：服务器地址 / 用户名 / 密码 / 账号名。
/// 支持已保存账号快速切换。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _serverController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 预填已保存账号信息，方便快速登录。
    final AccountEntry? account = AccountStore.instance.activeAccount;
    if (account != null) {
      _serverController.text = account.serverUrl;
      _userController.text = account.userName;
      _nameController.text = account.displayName;
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final String serverUrl = _serverController.text.trim();
    final String user = _userController.text.trim();
    final String password = _passwordController.text;

    if (serverUrl.isEmpty || user.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写服务器地址、用户名和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.login(
        serverUrl: serverUrl,
        user: user,
        password: password,
        displayName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.music_note, size: 72, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    '登录飞牛音乐',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '连接你的飞牛私有云音乐服务',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _serverController,
                    decoration: const InputDecoration(
                      labelText: '服务器地址',
                      hintText: 'http://10.0.2.2:8818（开发 mock）',
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _userController,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '账号名称（可选）',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('登录'),
                  ),
                  _buildSavedAccounts(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSavedAccounts(BuildContext context) {
    return ValueListenableBuilder<List<AccountEntry>>(
      valueListenable: AccountStore.instance.accounts,
      builder: (context, accounts, _) {
        if (accounts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 24),
            Text('已保存账号', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            ...accounts.map((AccountEntry a) {
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(a.displayName),
                  subtitle: Text(a.serverUrl),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final NavigatorState navigator = Navigator.of(context);
                    setState(() {
                      _serverController.text = a.serverUrl;
                      _userController.text = a.userName;
                      _nameController.text = a.displayName;
                      _passwordController.clear();
                    });
                    await AuthService.instance.switchToAccount(a);
                    navigator.popUntil((Route<dynamic> r) => r.isFirst);
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
