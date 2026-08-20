import 'dart:convert';

/// 单个飞牛账号。
class AccountEntry {
  const AccountEntry({
    required this.id,
    required this.serverUrl,
    required this.userName,
    required this.displayName,
    this.token,
  });

  /// 本地唯一标识。
  final String id;
  final String serverUrl;
  final String userName;
  final String displayName;
  final String? token;

  AccountEntry copyWith({String? token}) {
    return AccountEntry(
      id: id,
      serverUrl: serverUrl,
      userName: userName,
      displayName: displayName,
      token: token ?? this.token,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'serverUrl': serverUrl,
        'userName': userName,
        'displayName': displayName,
        if (token != null) 'token': token,
      };

  factory AccountEntry.fromJson(Map<String, Object?> json) {
    return AccountEntry(
      id: json['id'] as String? ?? '',
      serverUrl: json['serverUrl'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      token: json['token'] as String?,
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
