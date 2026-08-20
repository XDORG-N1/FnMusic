import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/listening_accumulator.dart';
import 'package:fnmusic/app/state/player_state.dart';
import 'package:fnmusic/app/state/song_state.dart';

void main() {
  const SongEntity songA = SongEntity(
    guid: 'song-a',
    title: '歌曲A',
    artistDisplay: '歌手A',
    albumDisplay: '专辑A',
    coverId: 'cover-a',
    durationMs: 210000,
  );
  const SongEntity songB = SongEntity(
    guid: 'song-b',
    title: '歌曲B',
    artistDisplay: '歌手B',
    durationMs: 180000,
  );

  PlayerSnapshot playing(SongEntity song) => PlayerSnapshot(
        song: song,
        queue: <SongEntity>[song],
        index: 0,
        isPlaying: true,
        position: const Duration(seconds: 10),
        duration: const Duration(seconds: 60),
        bufferedPosition: const Duration(seconds: 60),
      );

  PlayerSnapshot paused(SongEntity? song) {
    final int? durationMs = song?.durationMs;
    return PlayerSnapshot(
      song: song,
      queue: song == null ? const <SongEntity>[] : <SongEntity>[song],
      index: song == null ? -1 : 0,
      isPlaying: false,
      position: Duration.zero,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
      bufferedPosition: Duration.zero,
    );
  }

  group('ListeningAccumulator', () {
    test('未播放或空曲目不产生增量', () {
      final ListeningAccumulator acc = ListeningAccumulator();
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);

      expect(acc.onSnapshot(paused(null), t0), isNull);
      expect(acc.onSnapshot(paused(songA), t0), isNull);
      expect(acc.takeAll(), isNull);
    });

    test('首个播放快照只开积累，不产出', () {
      final ListeningAccumulator acc = ListeningAccumulator();
      expect(acc.onSnapshot(playing(songA), DateTime(2026, 8, 20, 10, 0, 0)),
          isNull);
    });

    test('连续快照累计时长，达到阈值产出并计数一次', () {
      final ListeningAccumulator acc = ListeningAccumulator(
        flushThresholdMs: 1000,
        playCountThresholdMs: 3000,
      );
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);

      // t0 开积累，t0+1s 产出 1000ms（songListen 未满 1000？恰好满阈值）。
      acc.onSnapshot(playing(songA), t0);
      final StatsDelta? first =
          acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 1)));
      expect(first, isNotNull);
      expect(first!.songId, 'song-a');
      expect(first.songListenMs, 1000);
      expect(first.songPlayCount, 0);
      expect(first.dayListenMs, 1000);
    });

    test('单曲累计满 playCountThresholdMs 计一次播放，且只计一次', () {
      final ListeningAccumulator acc = ListeningAccumulator(
        flushThresholdMs: 5000,
        playCountThresholdMs: 3000,
      );
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);
      acc.onSnapshot(playing(songA), t0);

      // +2s：累计 2000ms，未达 3000ms 播放阈值。
      acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 2)));
      // +4s：累计 4000ms，达阈值 → 计 1 次播放（尚未满 5000ms flush）。
      final StatsDelta? early =
          acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 4)));
      expect(early, isNull);
      // +6s：累计 6000ms → 触发落库，带出 1 次播放。
      final StatsDelta? d1 =
          acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 6)));
      expect(d1, isNotNull);
      expect(d1!.songPlayCount, 1);
      expect(d1.dayPlayCount, 1);
      expect(d1.songListenMs, 6000);

      // 继续累计：同一首歌不再重复计次。
      acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 8)));
      acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 10)));
      final StatsDelta? d2 =
          acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 12)));
      expect(d2, isNotNull);
      expect(d2!.songPlayCount, 0);
    });

    test('切歌时带出上一首的累计，且增量归属旧曲', () {
      final ListeningAccumulator acc = ListeningAccumulator(
        flushThresholdMs: 5000,
        playCountThresholdMs: 3000,
      );
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);
      acc.onSnapshot(playing(songA), t0);
      acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 2)));

      // 切到 songB。
      final StatsDelta? delta = acc.onSnapshot(
        playing(songB),
        t0.add(const Duration(seconds: 3)),
      );
      expect(delta, isNotNull);
      expect(delta!.songId, 'song-a');
      expect(delta.song!.guid, 'song-a');
      expect(delta.songListenMs, 2000);
    });

    test('暂停结束本段累计并取走增量', () {
      final ListeningAccumulator acc = ListeningAccumulator(
        flushThresholdMs: 5000,
        playCountThresholdMs: 3000,
      );
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);
      acc.onSnapshot(playing(songA), t0);
      acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 2)));

      final StatsDelta? delta =
          acc.onSnapshot(paused(songA), t0.add(const Duration(seconds: 3)));
      expect(delta, isNotNull);
      expect(delta!.songListenMs, 2000);
      expect(delta.song!.guid, 'song-a');
      // 暂停后无待落库增量。
      expect(acc.takeAll(), isNull);
    });

    test('快照间隔超过 maxTickGapMs 时本次间隔封顶', () {
      final ListeningAccumulator acc = ListeningAccumulator(
        maxTickGapMs: 1000,
        flushThresholdMs: 1500,
      );
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);
      acc.onSnapshot(playing(songA), t0);

      // 间隔 10s，但封顶 1s → 只累计 1000ms，未满 1500ms flush。
      final StatsDelta? delta =
          acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 10)));
      expect(delta, isNull);
      // 再 +1s：累计到 2000ms，满阈值落库，验证只封顶了那一次间隔。
      final StatsDelta? d2 =
          acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 11)));
      expect(d2, isNotNull);
      expect(d2!.songListenMs, 2000);
    });

    test('takeAll 手动取走未落库增量', () {
      final ListeningAccumulator acc = ListeningAccumulator(
        flushThresholdMs: 5000,
      );
      final DateTime t0 = DateTime(2026, 8, 20, 10, 0, 0);
      acc.onSnapshot(playing(songA), t0);
      acc.onSnapshot(playing(songA), t0.add(const Duration(seconds: 2)));

      final StatsDelta? delta = acc.takeAll();
      expect(delta, isNotNull);
      expect(delta!.songListenMs, 2000);
      expect(acc.takeAll(), isNull);
    });
  });
}
