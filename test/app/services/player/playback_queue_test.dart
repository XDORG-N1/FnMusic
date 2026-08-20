import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/player/playback_queue.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/app/state/song_state.dart';

void main() {
  List<SongEntity> songs(int n) =>
      List<SongEntity>.generate(n, (int i) => SongEntity(guid: 's$i', title: '曲$i'));

  group('PlaybackQueue.loop 模式', () {
    test('队尾 next 回卷到队首', () {
      final q = PlaybackQueue(items: songs(3), currentIndex: 2);
      expect(q.nextIndex(), 0);
    });

    test('previous 从队首回卷到队尾', () {
      final q = PlaybackQueue(items: songs(3), currentIndex: 0);
      expect(q.previousIndex(), 2);
    });

    test('中间索引正常推进', () {
      final q = PlaybackQueue(items: songs(3), currentIndex: 1);
      expect(q.nextIndex(), 2);
      expect(q.previousIndex(), 0);
    });
  });

  group('PlaybackQueue.single 模式', () {
    test('next/previous 均返回当前索引（引擎自行重复）', () {
      final q = PlaybackQueue(
        items: songs(3),
        currentIndex: 1,
      )..mode = PlaybackMode.single;
      expect(q.nextIndex(), 1);
      expect(q.previousIndex(), 1);
    });
  });

  group('PlaybackQueue.shuffle 模式', () {
    test('同 seed 洗牌顺序可复现', () {
      final List<int> a = PlaybackQueue.buildShuffleOrder(10, 42);
      final List<int> b = PlaybackQueue.buildShuffleOrder(10, 42);
      expect(a, b);
      // 是排列（0..9 各一次）。
      expect(a.toSet(), <int>{0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
    });

    test('不同 seed 顺序不同', () {
      expect(PlaybackQueue.buildShuffleOrder(10, 1),
          isNot(PlaybackQueue.buildShuffleOrder(10, 2)));
    });

    test('next 沿洗牌顺序推进', () {
      final q = PlaybackQueue(items: songs(5), currentIndex: 0)
        ..mode = PlaybackMode.shuffle
        ..shuffleSeed = 7
        ..rebuildShuffleOrder();
      // 从 currentIndex 出发沿 shuffleOrder 前进。
      final pos = q.shuffleOrder.indexOf(q.currentIndex);
      final expected = pos + 1 < q.shuffleOrder.length ? q.shuffleOrder[pos + 1] : null;
      expect(q.nextIndex(), expected);
    });

    test('耗尽后 reshuffleAndContinue 返回新顺序首元素', () {
      final q = PlaybackQueue(items: songs(3), currentIndex: 0)
        ..mode = PlaybackMode.shuffle
        ..shuffleSeed = 5
        ..rebuildShuffleOrder();
      // 把 currentIndex 挪到 shuffleOrder 末尾 → next 为 null。
      q.currentIndex = q.shuffleOrder.last;
      expect(q.nextIndex(), isNull);
      final int? next = q.reshuffleAndContinue();
      expect(next, isNotNull);
      expect(q.shuffleSeed, isNot(5));
    });
  });

  group('PlaybackQueue 持久化', () {
    test('toJson/fromJson 往返一致', () {
      final q = PlaybackQueue(items: songs(3), currentIndex: 1)
        ..mode = PlaybackMode.shuffle
        ..shuffleSeed = 99
        ..rebuildShuffleOrder();
      final restored = PlaybackQueue.fromJson(q.toJson());
      expect(restored.items.length, q.items.length);
      expect(restored.items.first.guid, q.items.first.guid);
      expect(restored.currentIndex, 1);
      expect(restored.mode, PlaybackMode.shuffle);
      expect(restored.shuffleSeed, 99);
      expect(restored.shuffleOrder, q.shuffleOrder);
    });
  });

  group('PlaybackQueue.replace', () {
    test('替换队列并定位 startIndex', () {
      final q = PlaybackQueue(items: songs(2), currentIndex: 0);
      q.replace(songs(4), startIndex: 3);
      expect(q.currentIndex, 3);
      expect(q.items.length, 4);
    });

    test('空队列 currentIndex 置 -1', () {
      final q = PlaybackQueue(items: songs(2), currentIndex: 0);
      q.replace(const <SongEntity>[]);
      expect(q.currentIndex, -1);
      expect(q.isEmpty, isTrue);
    });

    test('startIndex 越界时 clamp', () {
      final q = PlaybackQueue(items: songs(2), currentIndex: 0);
      q.replace(songs(3), startIndex: 10);
      expect(q.currentIndex, 2);
    });
  });
}
