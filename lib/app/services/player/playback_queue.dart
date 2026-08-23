import 'dart:math' as math;

import '../../state/player_state.dart';
import '../../state/song_state.dart';

/// 播放队列与导航（纯逻辑，可单测）。
///
/// PlayerService 以此为唯一真源驱动播放，并把状态镜像到 [AppPlayerState]。
/// 模式语义（与原设计一致）：
/// - [PlaybackMode.sequential]：顺序播放，到队尾/队首停止（next 返回 null）；
/// - [PlaybackMode.loop]：列表循环，队尾 next 回卷到队首；
/// - [PlaybackMode.shuffle]：按 Fisher-Yates 洗牌顺序导航，耗尽后重新洗牌；
/// - [PlaybackMode.single]：单曲循环，由引擎自行重复。
class PlaybackQueue {
  PlaybackQueue({
    List<SongEntity> items = const <SongEntity>[],
    this.currentIndex = -1,
    this.mode = PlaybackMode.loop,
    this.shuffleSeed = 0,
  }) : items = List<SongEntity>.of(items) {
    rebuildShuffleOrder();
  }

  List<SongEntity> items;
  int currentIndex;
  PlaybackMode mode;

  /// 洗牌种子：持久化后随机顺序可复现。
  int shuffleSeed;

  /// 随机播放时的逻辑顺序（元素的逻辑索引序列）；非 shuffle 为恒等序列。
  late List<int> shuffleOrder;

  bool get isEmpty => items.isEmpty;

  SongEntity? get current =>
      (currentIndex >= 0 && currentIndex < items.length) ? items[currentIndex] : null;

  /// 替换整个队列并定位 [startIndex]（默认 0）。
  void replace(
    List<SongEntity> songs, {
    int? startIndex,
    PlaybackMode? newMode,
    int? newSeed,
  }) {
    items = List<SongEntity>.of(songs);
    if (newMode != null) mode = newMode;
    if (newSeed != null) shuffleSeed = newSeed;
    rebuildShuffleOrder();
    currentIndex = items.isEmpty
        ? -1
        : (startIndex ?? 0).clamp(0, items.length - 1);
  }

  /// 重建随机顺序（仅在 shuffle 模式需要）。seed 不变时结果可复现。
  void rebuildShuffleOrder() {
    final int length = items.length;
    if (mode == PlaybackMode.shuffle && length > 1) {
      shuffleOrder = buildShuffleOrder(length, shuffleSeed);
    } else {
      shuffleOrder = List<int>.generate(length, (int i) => i);
    }
  }

  /// 下一首逻辑索引；null = 无法继续（shuffle 耗尽 / 顺序到队尾 / 空队列）。
  int? nextIndex() {
    if (items.isEmpty) return null;
    switch (mode) {
      case PlaybackMode.single:
        return currentIndex;
      case PlaybackMode.shuffle:
        final int pos = shuffleOrder.indexOf(currentIndex);
        if (pos < 0 || pos + 1 >= shuffleOrder.length) return null;
        return shuffleOrder[pos + 1];
      case PlaybackMode.loop:
        return currentIndex + 1 < items.length ? currentIndex + 1 : 0;
      case PlaybackMode.sequential:
        return currentIndex + 1 < items.length ? currentIndex + 1 : null;
    }
  }

  /// 上一首逻辑索引；null = 无法继续（shuffle 到队首 / 顺序到队首 / 空队列）。
  int? previousIndex() {
    if (items.isEmpty) return null;
    switch (mode) {
      case PlaybackMode.single:
        return currentIndex;
      case PlaybackMode.shuffle:
        final int pos = shuffleOrder.indexOf(currentIndex);
        if (pos <= 0) return null;
        return shuffleOrder[pos - 1];
      case PlaybackMode.loop:
        return currentIndex <= 0 ? items.length - 1 : currentIndex - 1;
      case PlaybackMode.sequential:
        return currentIndex > 0 ? currentIndex - 1 : null;
    }
  }

  /// 当前歌开始播放后是否自动前进（single 由引擎循环，不自动前进）。
  bool get shouldAutoAdvance => mode != PlaybackMode.single;

  /// shuffle 耗尽后重新洗牌（新种子）并从新顺序第一首继续。
  /// 返回新索引；非 shuffle 或空队列返回 null。
  int? reshuffleAndContinue() {
    if (mode != PlaybackMode.shuffle || items.isEmpty) return null;
    shuffleSeed = _nextSeed(shuffleSeed);
    rebuildShuffleOrder();
    return shuffleOrder.isNotEmpty ? shuffleOrder.first : null;
  }

  /// Fisher-Yates 洗牌（确定性：同 seed 同长度 → 同顺序，可持久化复现）。
  static List<int> buildShuffleOrder(int length, int seed) {
    if (length <= 1) return List<int>.generate(length, (int i) => i);
    final math.Random rng = math.Random(seed);
    final List<int> list = List<int>.generate(length, (int i) => i);
    for (var i = length - 1; i > 0; i--) {
      final int j = rng.nextInt(i + 1);
      final int t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
    return list;
  }

  static int _nextSeed(int seed) => (seed + 1) % (1 << 31);

  /// 生成新的随机种子（运行时随机；测试用固定 seed 复现顺序）。
  static int newSeed() => math.Random().nextInt(1 << 31);

  // ---------- 持久化 ----------

  Map<String, Object?> toJson() => <String, Object?>{
        'items': items.map((SongEntity e) => e.toJson()).toList(),
        'currentIndex': currentIndex,
        'mode': mode.name,
        'shuffleSeed': shuffleSeed,
        'shuffleOrder': shuffleOrder,
      };

  factory PlaybackQueue.fromJson(Map<String, Object?> json) {
    final List<SongEntity> items = (json['items'] as List<Object?>?)
            ?.whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> m) =>
                SongEntity.fromJson(m.cast<String, Object?>()))
            .toList() ??
        <SongEntity>[];
    return PlaybackQueue(
      items: items,
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? -1,
      mode: PlaybackMode.values.asNameMap()[json['mode']] ?? PlaybackMode.loop,
      shuffleSeed: (json['shuffleSeed'] as num?)?.toInt() ?? 0,
    );
  }
}
