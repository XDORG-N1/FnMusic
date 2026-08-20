import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/services/backup/backup_service.dart';
import 'app/services/listening_recorder_service.dart';
import 'app/services/media_notification_service.dart';
import 'app/services/player_service.dart';
import 'app/services/stats_service.dart';
import 'app/state/player_state.dart';
import 'app/state/settings_state.dart';

void _onPlayerSnapshot() {
  final PlayerSnapshot snap = AppPlayerState.instance.snapshot.value;
  // 听歌统计（song_stats / listening_days）与行为流水（report_events）。
  StatsService.instance.onSnapshot(snap);
  ListeningRecorderService.instance.onSnapshot(snap);
}

class _LifecycleFlushObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      // 退到后台：把未落库的收听累计与行为会话写盘。
      unawaited(StatsService.instance.flush());
      unawaited(ListeningRecorderService.instance.onLifecyclePause());
    }
  }
}

/// 进程级 SSL 证书校验覆盖。
///
/// 通过 [HttpOverrides.global] 安装，拦截进程内所有 [HttpClient]
/// （Dio 默认适配器、探测 Dio、CachedNetworkImage 等）。
/// [badCertificateCallback] 实时读取 [AppFnConnectionSettings.ignoreSsl]，
/// 开关动态度生效，无需重启 APP。默认开启以兼容自签名证书 /
/// 企业网关重签（Sangfor 等）的环境。
class _SslOverride extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (_, _, _) =>
        AppFnConnectionSettings.ignoreSsl.value;
    return client;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 进程级 SSL 覆盖：必须先于任何网络请求安装（读取 ignoreSsl 偏好）。
  HttpOverrides.global = _SslOverride();

  // Android 15 强制 edge-to-edge。
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 加载全部设置域（主题 / 引导状态等）。
  await SettingsState.loadAll();

  // 播放器：配置音频焦点 + 恢复上次播放状态。
  await FnPlayerService.instance.init();

  // 媒体通知（MediaSession / 通知栏 / Android Auto / 车载歌词）。
  // 内部自行判断是否已有播放内容；没有则仅注册 MediaSession 供
  // Android Auto 发现，首次播放时再完成 handler 初始化。
  await MediaNotificationService.init();

  // 听歌统计：订阅播放快照；退后台时兜底落库。
  AppPlayerState.instance.snapshot.addListener(_onPlayerSnapshot);
  WidgetsBinding.instance.addObserver(_LifecycleFlushObserver());

  // 自动备份：每天首次打开时向已配置的 WebDAV 目标上传（静默失败）。
  unawaited(BackupService.instance.maybeAutoBackupOnLaunch());

  runApp(const FnMusicApp());
}
