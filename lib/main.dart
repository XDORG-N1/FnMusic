import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const FnMusicApp());
}
