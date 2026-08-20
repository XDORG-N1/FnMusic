import 'package:flutter/foundation.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as fl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals.dart';

import '../../state/player_state.dart';
import '../../state/song_state.dart';
import '../player_service.dart';
import 'lyrics_parser.dart';
import 'lyrics_repository.dart';

enum LyricsLoadStatus { idle, loading, loaded, empty, failed }

class LyricsSnapshot {
  final LyricsLoadStatus status;
  final SongEntity? song;
  final fl.LyricModel? model;
  final Object? error;

  const LyricsSnapshot({
    required this.status,
    required this.song,
    required this.model,
    required this.error,
  });

  factory LyricsSnapshot.idle() {
    return const LyricsSnapshot(
      status: LyricsLoadStatus.idle,
      song: null,
      model: null,
      error: null,
    );
  }

  LyricsSnapshot copyWith({
    LyricsLoadStatus? status,
    SongEntity? song,
    Object? error,
    fl.LyricModel? model,
  }) {
    return LyricsSnapshot(
      status: status ?? this.status,
      song: song ?? this.song,
      model: model ?? this.model,
      error: error,
    );
  }
}

/// 歌词服务单例：负责歌词的加载、解析、高亮推进与点按跳转。
///
/// 与播放器的同步通过 [AppPlayerState] 的 ValueNotifier 完成（当前歌曲 /
/// 播放位置 / 播放状态），进度由 [LyricController.setProgress] 驱动。
/// 歌词页与逐字歌词预览共用同一 controller 与配色设置。
class LyricsService {
  static final LyricsService instance = LyricsService._internal();

  static const String _prefsViewForceKaraoke = 'lyrics_view_force_karaoke';
  static const String _prefsViewInactiveColor = 'lyrics_view_inactive_color';
  static const String _prefsViewActiveColor = 'lyrics_view_active_color';
  static const String _prefsViewHighlightColor = 'lyrics_view_highlight_color';

  final LyricsRepository _repo = LyricsRepository();
  final FnPlayerService _player = FnPlayerService.instance;
  final AppPlayerState _state = AppPlayerState.instance;
  final LyricController controller = LyricController();
  final ValueNotifier<LyricsSnapshot> snapshot = ValueNotifier(
    LyricsSnapshot.idle(),
  );
  final ValueNotifier<String?> currentLineText = ValueNotifier(null);
  final ValueNotifier<int> viewSettingsTick = ValueNotifier(0);

  /// 歌词页自定义颜色的镜像，供播放页逐字歌词保持一致。
  final ValueNotifier<int?> viewInactiveColor = ValueNotifier(null);
  final ValueNotifier<int?> viewActiveColor = ValueNotifier(null);
  final ValueNotifier<int?> viewHighlightColor = ValueNotifier(null);
  late final snapshotSignal = signal(LyricsSnapshot.idle());
  late final viewSettingsTickSignal = signal(0);
  late final activeIndexSignal = signal(controller.activeIndexNotifiter.value);
  late final lyricModelSignal = signal(controller.lyricNotifier.value);
  late final isSelectingSignal = signal(controller.isSelectingNotifier.value);
  late final selectedIndexSignal = signal(
    controller.selectedIndexNotifier.value,
  );

  int _loadSeq = 0;
  bool _viewForceKaraoke = false;

  LyricsService._internal() {
    snapshot.addListener(() => snapshotSignal.value = snapshot.value);
    viewSettingsTick.addListener(
      () => viewSettingsTickSignal.value = viewSettingsTick.value,
    );
    controller.activeIndexNotifiter.addListener(
      () => activeIndexSignal.value = controller.activeIndexNotifiter.value,
    );
    controller.activeIndexNotifiter.addListener(_onActiveIndexChanged);
    controller.lyricNotifier.addListener(
      () => lyricModelSignal.value = controller.lyricNotifier.value,
    );
    controller.isSelectingNotifier.addListener(
      () => isSelectingSignal.value = controller.isSelectingNotifier.value,
    );
    controller.selectedIndexNotifier.addListener(
      () => selectedIndexSignal.value = controller.selectedIndexNotifier.value,
    );
    controller.setOnTapLineCallback((pos) {
      controller.stopSelection();
      _player.seek(pos);
    });
    _state.currentSong.addListener(_onSongChanged);
    _state.position.addListener(_onPositionChanged);
    _state.isPlaying.addListener(_onPlayingChanged);
    viewSettingsTick.addListener(_reloadViewColorPrefs);
    refreshSettings();
    _reloadViewColorPrefs();
    _onSongChanged();
  }

  void notifyViewSettingsChanged() {
    viewSettingsTick.value = viewSettingsTick.value + 1;
  }

  Future<void> _reloadViewColorPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    viewInactiveColor.value = prefs.getInt(_prefsViewInactiveColor);
    viewActiveColor.value = prefs.getInt(_prefsViewActiveColor);
    viewHighlightColor.value = prefs.getInt(_prefsViewHighlightColor);
  }

  Future<void> refreshSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _viewForceKaraoke = prefs.getBool(_prefsViewForceKaraoke) ?? false;
  }

  /// 是否强制逐字卡拉OK（当前行按字高亮）。
  bool get forceKaraoke => _viewForceKaraoke;

  void _onSongChanged() {
    final song = _state.currentSong.value;
    _loadForSong(song);
  }

  void _onPositionChanged() {
    controller.setProgress(_state.position.value);
  }

  void _onPlayingChanged() {
    // 播放状态影响歌词自动滚动暂停/恢复，由 LyricView 内部处理。
  }

  void _onActiveIndexChanged() {
    _updateCurrentLineText(controller.activeIndexNotifiter.value);
  }

  void reloadCurrentSong() {
    _loadForSong(_state.currentSong.value);
  }

  Future<void> _loadForSong(SongEntity? song) async {
    final seq = ++_loadSeq;
    snapshot.value = snapshot.value.copyWith(
      status: LyricsLoadStatus.loading,
      song: song,
      model: null,
      error: null,
    );
    controller.lyricNotifier.value = null;
    currentLineText.value = null;

    if (song == null) {
      snapshot.value = snapshot.value.copyWith(
        status: LyricsLoadStatus.empty,
        song: null,
        model: null,
        error: null,
      );
      return;
    }

    try {
      await refreshSettings();
      var lrc = await _repo.loadLrc(song);
      if (seq != _loadSeq) return;

      if (lrc == null || lrc.trim().isEmpty) {
        snapshot.value = snapshot.value.copyWith(
          status: LyricsLoadStatus.empty,
          song: song,
          model: null,
          error: null,
        );
        return;
      }

      final model = LyricsParser.buildModelFromRaw(
        lrc,
        songDuration: (song.durationMs == null)
            ? null
            : Duration(milliseconds: song.durationMs!),
        predictDuration: false,
        forceKaraoke: _viewForceKaraoke,
      );
      if (kDebugMode) {
        final translationCount = model.lines
            .where((line) => (line.translation ?? '').trim().isNotEmpty)
            .length;
        debugPrint(
          '[Lyrics] parsed ${model.lines.length} lines, '
          '$translationCount translations for ${song.title}',
        );
      }
      controller.loadLyricModel(model);
      _updateCurrentLineText(controller.activeIndexNotifiter.value);
      snapshot.value = snapshot.value.copyWith(
        status: LyricsLoadStatus.loaded,
        song: song,
        model: model,
        error: null,
      );
    } catch (e) {
      if (seq != _loadSeq) return;
      snapshot.value = snapshot.value.copyWith(
        status: LyricsLoadStatus.failed,
        song: song,
        model: null,
        error: e,
      );
    }
  }

  void _updateCurrentLineText(int index) {
    final model = controller.lyricNotifier.value;
    if (model == null || model.lines.isEmpty) {
      currentLineText.value = null;
      return;
    }
    if (index < 0 || index >= model.lines.length) {
      currentLineText.value = null;
      return;
    }
    final text = model.lines[index].text.trim();
    currentLineText.value = text.isEmpty ? null : text;
  }

  // ---------------------------------------------------------------------
  // 歌词样式设置（歌词设置页接线）
  // ---------------------------------------------------------------------

  /// 设置强制逐字卡拉OK（当前行按字高亮）。
  Future<void> setForceKaraoke(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsViewForceKaraoke, value);
    await refreshSettings();
    notifyViewSettingsChanged();
  }

  /// 设置自定义歌词配色。任一为 null 表示不改动该项。
  Future<void> setViewColors({
    int? inactive,
    int? active,
    int? highlight,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (inactive != null) {
      await prefs.setInt(_prefsViewInactiveColor, inactive);
    }
    if (active != null) {
      await prefs.setInt(_prefsViewActiveColor, active);
    }
    if (highlight != null) {
      await prefs.setInt(_prefsViewHighlightColor, highlight);
    }
    await _reloadViewColorPrefs();
    notifyViewSettingsChanged();
  }

  /// 清除自定义歌词配色，恢复跟随主题。
  Future<void> clearViewColors() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsViewInactiveColor);
    await prefs.remove(_prefsViewActiveColor);
    await prefs.remove(_prefsViewHighlightColor);
    await _reloadViewColorPrefs();
    notifyViewSettingsChanged();
  }
}
