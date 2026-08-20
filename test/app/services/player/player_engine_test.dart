import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/feiniu/transcode_service.dart';
import 'package:fnmusic/app/services/player/playback_router.dart';
import 'package:fnmusic/app/services/player/player_engine.dart';
import 'package:fnmusic/app/services/player_service.dart';
import 'package:fnmusic/app/state/player_state.dart';

void main() {
  group('routeForFormat', () {
    test('普通格式走 just_audio', () {
      expect(routeForFormat('mp3'), EngineKind.justAudio);
      expect(routeForFormat('FLAC'), EngineKind.justAudio);
      expect(routeForFormat('aac'), EngineKind.justAudio);
      expect(routeForFormat('wav'), EngineKind.justAudio);
      expect(routeForFormat('ogg'), EngineKind.justAudio);
    });

    test('未知/空格式走 just_audio', () {
      expect(routeForFormat(null), EngineKind.justAudio);
      expect(routeForFormat(''), EngineKind.justAudio);
    });

    test('黑名单格式走 media_kit', () {
      expect(routeForFormat('dsf'), EngineKind.mediaKit);
      expect(routeForFormat('DFF'), EngineKind.mediaKit);
      expect(routeForFormat('wma'), EngineKind.mediaKit);
      expect(routeForFormat('ape'), EngineKind.mediaKit);
      expect(routeForFormat('dts'), EngineKind.mediaKit);
      expect(routeForFormat('aiff'), EngineKind.mediaKit);
    });

    test('黑名单 codec 优先于容器走 media_kit', () {
      // m4a 容器本身不走 media_kit，但内嵌 eac3/alac 设备解码不可靠。
      expect(routeForFormat('m4a', codec: 'eac3'), EngineKind.mediaKit);
      expect(routeForFormat('m4a', codec: 'alac'), EngineKind.mediaKit);
      expect(routeForFormat('mp4', codec: 'truehd'), EngineKind.mediaKit);
      // 常规 codec 不受影响。
      expect(routeForFormat('m4a', codec: 'aac'), EngineKind.justAudio);
      expect(routeForFormat('m4a', codec: 'flac'), EngineKind.justAudio);
    });

    test('Windows 桌面端全量 media_kit', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(routeForFormat('mp3'), EngineKind.mediaKit);
      expect(routeForFormat(null), EngineKind.mediaKit);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('FnTranscodeService 分类', () {
    test('isMediaKitFormat 大小写不敏感', () {
      expect(FnTranscodeService.isMediaKitFormat('DSF'), isTrue);
      expect(FnTranscodeService.isMediaKitFormat('flac'), isFalse);
    });

    test('isMediaKitCodec null 安全', () {
      expect(FnTranscodeService.isMediaKitCodec(null), isFalse);
      expect(FnTranscodeService.isMediaKitCodec(''), isFalse);
      expect(FnTranscodeService.isMediaKitCodec('EAC3'), isTrue);
      expect(FnTranscodeService.isMediaKitCodec('aac'), isFalse);
    });
  });

  group('FnPlayerService.advanceSequentialIndex', () {
    test('顺序模式向前推进', () {
      expect(
        FnPlayerService.advanceSequentialIndex(0, 5, PlaybackMode.sequential, true),
        1,
      );
    });

    test('顺序模式队尾停止返回 -1', () {
      expect(
        FnPlayerService.advanceSequentialIndex(4, 5, PlaybackMode.sequential, true),
        -1,
      );
    });

    test('顺序模式队首向前（上一首）返回 -1', () {
      expect(
        FnPlayerService.advanceSequentialIndex(0, 5, PlaybackMode.sequential, false),
        -1,
      );
    });

    test('列表循环首尾回卷', () {
      expect(
        FnPlayerService.advanceSequentialIndex(4, 5, PlaybackMode.loop, true),
        0,
      );
      expect(
        FnPlayerService.advanceSequentialIndex(0, 5, PlaybackMode.loop, false),
        4,
      );
    });

    test('单曲循环始终返回当前', () {
      expect(
        FnPlayerService.advanceSequentialIndex(2, 5, PlaybackMode.single, true),
        2,
      );
    });
  });
}
