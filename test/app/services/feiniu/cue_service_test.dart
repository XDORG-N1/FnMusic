import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/cue_service.dart';

void main() {
  group('FnCueService.computeOffsets', () {
    FnTrack cueTrack({
      required String guid,
      required String path,
      int duration = 1000,
      int? trackNo,
      int? discNo,
      String albumGuid = 'alb_1',
    }) {
      return FnTrack(
        guid: guid,
        title: guid,
        isCue: true,
        duration: duration,
        trackNo: trackNo,
        discNo: discNo,
        album: FnAlbum(guid: albumGuid, name: '专辑'),
        audioSpec: FnAudioSpec(path: path),
      );
    }

    test('非 CUE 曲目不参与计算', () {
      final tracks = <FnTrack>[
        FnTrack(
          guid: 't1',
          title: '普通曲',
          duration: 5000,
          album: const FnAlbum(guid: 'alb_1', name: 'a'),
        ),
      ];
      expect(FnCueService.computeOffsets(tracks), isEmpty);
    });

    test('同一镜像内按 (discNo, trackNo) 累计偏移', () {
      final tracks = <FnTrack>[
        cueTrack(guid: 't1', path: '/f.flac', duration: 10000, trackNo: 1),
        cueTrack(guid: 't2', path: '/f.flac', duration: 20000, trackNo: 2),
        cueTrack(guid: 't3', path: '/f.flac', duration: 15000, trackNo: 3),
      ];
      final offsets = FnCueService.computeOffsets(tracks);
      expect(offsets['t1'], 0);
      expect(offsets['t2'], 10000);
      expect(offsets['t3'], 30000);
    });

    test('数组乱序时仍按 trackNo 排序', () {
      final tracks = <FnTrack>[
        cueTrack(guid: 't3', path: '/f.flac', duration: 15000, trackNo: 3),
        cueTrack(guid: 't1', path: '/f.flac', duration: 10000, trackNo: 1),
        cueTrack(guid: 't2', path: '/f.flac', duration: 20000, trackNo: 2),
      ];
      final offsets = FnCueService.computeOffsets(tracks);
      expect(offsets['t1'], 0);
      expect(offsets['t2'], 10000);
      expect(offsets['t3'], 30000);
    });

    test('不同物理文件 / 不同专辑分属不同镜像', () {
      final tracks = <FnTrack>[
        cueTrack(guid: 't1', path: '/a.flac', duration: 10000, trackNo: 1),
        cueTrack(guid: 't2', path: '/b.flac', duration: 10000, trackNo: 1),
        cueTrack(
          guid: 't3',
          path: '/a.flac',
          duration: 20000,
          trackNo: 1,
          albumGuid: 'alb_2',
        ),
      ];
      final offsets = FnCueService.computeOffsets(tracks);
      // 各自独立镜像，起始均为 0。
      expect(offsets['t1'], 0);
      expect(offsets['t2'], 0);
      expect(offsets['t3'], 0);
    });

    test('trackNo 缺失时回退到数组原始顺序', () {
      final tracks = <FnTrack>[
        cueTrack(guid: 'tA', path: '/f.flac', duration: 10000),
        cueTrack(guid: 'tB', path: '/f.flac', duration: 20000),
      ];
      final offsets = FnCueService.computeOffsets(tracks);
      expect(offsets['tA'], 0);
      expect(offsets['tB'], 10000);
    });

    test('同一物理文件内多碟：按 discNo 排序后跨碟累计', () {
      // 现实场景中不同碟通常是不同物理文件（不同 path → 分属不同镜像）；
      // 这里构造极端情况验证排序与累计逻辑：同一文件内按 (discNo, trackNo)
      // 排序，起始偏移为前序曲目时长之和（跨碟连续累计）。
      final tracks = <FnTrack>[
        cueTrack(guid: 'd2t1', path: '/f.flac', duration: 1000, discNo: 2, trackNo: 1),
        cueTrack(guid: 'd1t2', path: '/f.flac', duration: 2000, discNo: 1, trackNo: 2),
        cueTrack(guid: 'd1t1', path: '/f.flac', duration: 3000, discNo: 1, trackNo: 1),
        cueTrack(guid: 'd2t2', path: '/f.flac', duration: 4000, discNo: 2, trackNo: 2),
      ];
      final offsets = FnCueService.computeOffsets(tracks);
      // 排序后：d1t1(0) → d1t2(+3000=3000) → d2t1(+2000=5000) → d2t2(+1000=6000)。
      expect(offsets['d1t1'], 0);
      expect(offsets['d1t2'], 3000);
      expect(offsets['d2t1'], 5000);
      expect(offsets['d2t2'], 6000);
    });

    test('无 audioSpec.path 的 CUE 曲目跳过', () {
      final tracks = <FnTrack>[
        FnTrack(
          guid: 't1',
          title: 't1',
          isCue: true,
          duration: 1000,
          album: const FnAlbum(guid: 'alb_1', name: 'a'),
        ),
      ];
      expect(FnCueService.computeOffsets(tracks), isEmpty);
    });
  });
}
