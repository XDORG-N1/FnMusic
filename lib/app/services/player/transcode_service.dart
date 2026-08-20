import 'package:flutter/foundation.dart';

import '../../state/song_state.dart';
import '../feiniu/api_client.dart';

/// 转码设置（P3 默认关闭；设置页接入后在此开关）。
abstract final class TranscodeSettings {
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// 转码格式（flac / mp3 / opus…）。
  static const String codec = 'flac';

  /// 大文件转码阈值（MB）。
  static int thresholdMb = 200;
}

/// 服务器转码服务（单例）。
///
/// 对 ExoPlayer 无法解码的格式请求服务器转码为 FLAC HLS（fMP4），
/// 只喂 just_audio（ExoPlayer）。media_kit 的 mpv FFmpeg 音频库未编入
/// hls demuxer，播不了 fMP4 HLS，因此转码歌强制走 just_audio。
///
/// 历史流程：DSF/DSD/WMA/APE/DTS/AIFF 等统一转 FLAC HLS 交给 media_kit。
/// 现已改为 media_kit 直连原始流，转码仅在用户显式开启时使用。
class FnTranscodeService {
  FnTranscodeService._();

  static final FnTranscodeService instance = FnTranscodeService._();

  /// 是否应转码（设置门控）。
  Future<bool> shouldTranscode(SongEntity song) async {
    if (!TranscodeSettings.enabled.value) return false;
    final String? format = song.format;
    if (format == null || format.isEmpty) return false;
    // 源格式与生效转码格式一致 → 无转码收益。
    if (format.trim().toLowerCase() == TranscodeSettings.codec) return false;
    return true;
  }

  /// 请求服务器转码，返回 HLS（m3u8）地址。
  ///
  /// 返回 `(url, playlist)`；失败抛 [ApiException]。
  Future<({String url, String playlist})> transcodeHlsFor(
    SongEntity song,
  ) async {
    final dynamic data = await ApiClient.instance.postData(
      '/track/transcode',
      body: <String, Object?>{
        'guid': song.guid,
        'codec': TranscodeSettings.codec,
      },
    );
    final Map<String, Object?> map = (data as Map<Object?, Object?>?)
            ?.cast<String, Object?>() ??
        const <String, Object?>{};
    final String url = map['url']?.toString() ?? '';
    final String playlist = map['playlist']?.toString() ?? '';
    if (url.isEmpty) throw const ApiException(-1, '转码失败：无 HLS 地址');
    return (url: url, playlist: playlist);
  }

  /// 从 [playlist]（m3u8 文本）提取分片（P6 转码整曲拼接时使用）。
  static List<String> segmentsFromM3u8(String playlist) {
    return playlist
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();
  }

  /// 相对分片地址 → 绝对地址（相对 `baseUrl` 解析）。
  static String resolveSegment(String segment, String baseUrl) {
    final Uri seg = Uri.parse(segment);
    if (seg.hasScheme) return segment;
    return Uri.parse(baseUrl).resolve(segment).toString();
  }
}
