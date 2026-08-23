import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../app/services/feiniu/access_code_service.dart';
import '../../app/services/feiniu/account_entry.dart';
import '../../app/services/feiniu/account_store.dart';
import '../../app/services/feiniu/api_client.dart';
import '../../app/services/feiniu/auth_service.dart';
import '../../app/services/feiniu/fn_connection_probe_service.dart';
import '../../app/services/feiniu/fn_models.dart';
import '../../app/state/settings_fn_state.dart';
import '../../components/dialog/access_code_dialog.dart';

/// 登录页：服务器地址（或 FNID）/ 用户名 / 密码 / 账号名。
///
/// 输入非 URL 且 ≥6 字符视为 **FNID**：通过 FN Connect 自动探测可达的
/// 服务器地址（内网 → 公网 IPv6 → 公网 IPv4 → 中继），再走登录。
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
  final FocusNode _passwordFocus = FocusNode();

  bool _loading = false;
  String? _error;
  OverlayEntry? _probeOverlay;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// 预填：已保存账号 → 其 FNID/地址；否则预填上次 FNID。
  Future<void> _prefill() async {
    await AppFnConnectionSettings.ensureLoaded();
    if (!mounted) return;
    final AccountEntry? account = AccountStore.instance.activeAccount;
    if (account != null) {
      _serverController.text =
          (account.fnId?.isNotEmpty == true) ? account.fnId! : account.serverUrl;
      _userController.text = account.userName;
      _nameController.text = account.displayName;
    } else if (AppFnConnectionSettings.lastFnId?.isNotEmpty == true) {
      _serverController.text = AppFnConnectionSettings.lastFnId!;
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _passwordFocus.dispose();
    _hideProbeOverlay();
    super.dispose();
  }

  /// 判断输入是否为 FNID（非 http/https 开头且 ≥6 字符）。
  bool _isFnId(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return false;
    }
    if (trimmed.length < 6) return false;
    return true;
  }

  Future<void> _login() async {
    final String serverUrlInput = _serverController.text.trim();
    final String user = _userController.text.trim();
    final String password = _passwordController.text;
    final String name = _nameController.text.trim();

    if (serverUrlInput.isEmpty || user.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写服务器地址、用户名和密码');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isFnId(serverUrlInput)) {
        await _fnLogin(serverUrlInput, user, password, name: name);
      } else {
        await _performLogin(serverUrlInput, user, password, name: name);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// FNID 登录：探测可达地址 → 保存连接信息 → 认证。
  Future<void> _fnLogin(
    String fnId,
    String user,
    String password, {
    String name = '',
  }) async {
    try {
      _showProbeOverlay();
      final ({String url, bool isRelay})? cache =
          AppFnConnectionSettings.cachedConnection;
      final ConnectionProbeResult result =
          await FnConnectionProbeService.instance.probeSmart(
        cachedUrl: cache?.url,
        cachedIsRelay: cache?.isRelay ?? false,
        fnId: fnId,
      );
      await AppFnConnectionSettings.saveProbeResult(
        fnId: fnId,
        url: result.serverUrl,
        method: result.probeMethod,
        isRelay: result.isRelay,
      );
      if (!mounted) return;
      _hideProbeOverlay();
      await _performLogin(
        result.serverUrl,
        user,
        password,
        relayMode: result.isRelay,
        fnId: fnId,
        name: name,
      );
    } catch (e) {
      if (!mounted) return;
      _hideProbeOverlay();
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// 执行实际登录（FNID 与普通地址共用）。
  Future<void> _performLogin(
    String serverUrl,
    String user,
    String password, {
    bool relayMode = false,
    String? fnId,
    String name = '',
  }) async {
    try {
      final bool proceed = await _ensureAccessCodeIfNeeded(
        serverUrl,
        isRelay: relayMode,
      );
      if (!proceed) return; // 用户取消安全码 → 中止登录
      await AuthService.instance.login(
        serverUrl: serverUrl,
        user: user,
        password: password,
        displayName: name.isEmpty ? null : name,
        relayMode: relayMode,
        fnId: fnId,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '登录失败：$e');
    }
  }

  /// 安全码检查（仅未存过才询问）：服务器要求访问码时弹输入框。
  Future<bool> _ensureAccessCodeIfNeeded(
    String serverUrl, {
    bool isRelay = false,
  }) async {
    if (AppFnConnectionSettings.accessCode != null) return true;
    try {
      final bool requires = await AccessCodeService.instance.requiresAccessCode(
        serverUrl,
        isRelay: isRelay,
      );
      if (requires && mounted) {
        final String? code = await AccessCodeDialog.show(
          context,
          baseUrl: serverUrl,
          isRelay: isRelay,
        );
        return code != null; // 取消 → false
      }
      return true;
    } on DioException {
      // 验证端点不可达（服务器未开启该端点 / 网络异常）→ 按不需要处理
      return true;
    }
  }

  /// 探测期间的全屏覆盖层。
  void _showProbeOverlay() {
    _probeOverlay = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: ColoredBox(
          color: Colors.black54,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const <Widget>[
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在探测连接…'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_probeOverlay!);
  }

  void _hideProbeOverlay() {
    _probeOverlay?.remove();
    _probeOverlay = null;
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
                      labelText: '服务器地址 / FNID',
                      hintText: 'http://10.0.2.2:8818 或 FN Connect 短码',
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
                    focusNode: _passwordFocus,
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
                  subtitle: Text(a.fnId?.isNotEmpty == true
                      ? a.fnId!
                      : a.serverUrl),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final NavigatorState navigator = Navigator.of(context);
                    setState(() {
                      _serverController.text = a.fnId?.isNotEmpty == true
                          ? a.fnId!
                          : a.serverUrl;
                      _userController.text = a.userName;
                      _nameController.text = a.displayName;
                      _passwordController.clear();
                    });
                    final bool switched =
                        await AuthService.instance.switchToAccount(a);
                    if (switched) {
                      // token 仍有效：静默切换进首页。
                      navigator.popUntil((Route<dynamic> r) => r.isFirst);
                    } else {
                      // 该账号已退出登录（token 已清除），无法静默登录：
                      // 预填已完成，提示并聚焦密码框等待重新输入。
                      _passwordFocus.requestFocus();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${a.displayName} 已退出登录，请重新输入密码',
                          ),
                        ),
                      );
                    }
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
