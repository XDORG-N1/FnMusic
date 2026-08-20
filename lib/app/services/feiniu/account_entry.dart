import 'dart:convert';

/// 单个飞牛账号。
class AccountEntry {
  const AccountEntry({
    required this.id,
    required this.serverUrl,
    required this.userName,
    required this.displayName,
    this.token,
    this.relayMode = false,
    this.accessCode,
    this.fnId,
  });

  /// 本地唯一标识。
  final String id;
  final String serverUrl;
  final String userName;
  final String displayName;
  final String? token;

  /// 是否通过中继链接连接（FN Connect 中继链路）。
  final bool relayMode;

  /// 该账号的安全码（可选，登录时验证后写入）。
  final String? accessCode;

  /// 若经 FNID 登录，记录用于探测的 FNID。
  final String? fnId;

  AccountEntry copyWith({
    String? token,
    bool? relayMode,
    String? Function()? accessCode,
    String? Function()? fnId,
  }) {
    return AccountEntry(
      id: id,
      serverUrl: serverUrl,
      userName: userName,
      displayName: displayName,
      token: token ?? this.token,
      relayMode: relayMode ?? this.relayMode,
      accessCode: accessCode != null ? accessCode() : this.accessCode,
      fnId: fnId != null ? fnId() : this.fnId,
    );
  }

  /// 去重键：同一 FNID + 同一用户名视为同一账号；无 FNID 时回退
  /// 「同一服务器 + 同一用户名」。
  ///
  /// FNID 账号的 serverUrl 是探测出来的最优地址（内网 IP / 公网 IP / 中继），
  /// 会随网络环境而改变；FNID 是设备的稳定标识，用它做去重键可让账号
  /// 跨地址切换保持唯一。
  String get identityKey {
    final id = fnId;
    if (id != null && id.isNotEmpty) {
      return 'fnid:${id.trim()}::$userName';
    }
    return '${serverUrl.trim()}::$userName';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'serverUrl': serverUrl,
        'userName': userName,
        'displayName': displayName,
        if (token != null) 'token': token,
        'relayMode': relayMode,
        if (accessCode != null) 'accessCode': accessCode,
        if (fnId != null) 'fnId': fnId,
      };

  factory AccountEntry.fromJson(Map<String, Object?> json) {
    return AccountEntry(
      id: json['id'] as String? ?? '',
      serverUrl: json['serverUrl'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      token: json['token'] as String?,
      relayMode: json['relayMode'] as bool? ?? false,
      accessCode: json['accessCode'] as String?,
      fnId: json['fnId'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static AccountEntry? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? json = jsonDecode(raw);
      if (json is Map<Object?, Object?>) {
        return AccountEntry.fromJson(json.cast<String, Object?>());
      }
    } catch (_) {}
    return null;
  }
}
