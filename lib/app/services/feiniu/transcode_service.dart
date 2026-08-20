import '../../state/song_state.dart';
import 'api_client.dart';

/// 转码/格式分类服务。
///
/// 两类职责：
/// 1. **引擎路由分类**（纯函数，无网络）：`isMediaKitFormat` / `isMediaKitCodec`
///    等，供 [FnPlayerService] 决定走 just_audio 还是 media_kit。
/// 2. **服务端 HLS 转码**（`POST /track/transcode`）：作为引擎回退链的最后一环
///    ——两个引擎都解码失败时，请求 NAS 转码为 HLS 用 just_audio（ExoPlayer）
///    ​播放。转码会话由 [FnPlayerService] 编排（发起/切歌时停止）。
///
/// 无声看门狗（risky-silence 容器在 codec 未知时的兜底）留待 P3 收尾按需补齐。
class FnTranscodeService {
  FnTranscodeService._();

  static final FnTranscodeService instance = FnTranscodeService._();

  /// just_audio（ExoPlayer）原生解码不了的**容器格式**黑名单：交给
  /// media_kit（FFmpeg 软解）。
  static const Set<String> unsupportedFormats = <String>{
    'dsf', 'dff', 'dsd',
    'wma', 'ape', 'dts',
    'aiff', 'ra', 'au',
    'dvf', 'tta', 'dss', 'mmf',
  };

  /// 交给 media_kit（FFmpeg）解码的**编码**黑名单：M4A/MP4 容器内常见的
  /// 环绕声/无损编码。ExoPlayer 的设备解码器（MediaCodec）对这些 codec 的
  /// 支持因设备而异：解码器不可用/静默失败时，进度条照常走但无声音。
  /// FFmpeg 全部原生解码，交给 media_kit 必定出声。
  static const Set<String> mediaKitCodecs = <String>{
    'eac3', 'ac3', 'alac', 'dts', 'truehd', 'mlp',
  };

  /// 容器格式是否交给 media_kit 解码。
  static bool isMediaKitFormat(String format) {
    final String f = format.trim().toLowerCase();
    return unsupportedFormats.contains(f);
  }

  /// codec 是否为 media_kit 专属（ExoPlayer 设备解码不可靠）。
  static bool isMediaKitCodec(String? codec) {
    if (codec == null || codec.isEmpty) return false;
    return mediaKitCodecs.contains(codec.trim().toLowerCase());
  }

  /// 可能内嵌风险 codec（EAC3/ALAC…）的容器格式。codec 未知（null）时，
  /// 这些容器需要无声看门狗兜底。
  static const Set<String> riskySilenceContainers = <String>{
    'm4a', 'm4b', 'm4p', 'mp4', 'aac', 'mov', '3gp', 'mka', 'mkv',
  };

  /// 容器是否可能内嵌风险 codec（codec 未知时据此判断是否需要看门狗）。
  static bool isRiskySilenceContainer(String? format) {
    if (format == null || format.isEmpty) return false;
    return riskySilenceContainers.contains(format.trim().toLowerCase());
  }

  /// 歌曲的格式（会话内无网络探测：直接取 `audioSpec.format`，缺失回退 null）。
  Future<String?> resolvedFormatFor(SongEntity song) async => song.format;

  /// 歌曲的 codec（同上）。
  Future<String?> resolvedCodecFor(SongEntity song) async => song.codec;

  /// 发起服务端 HLS 转码，返回**可直接播放**的播放列表地址；失败返回 null。
  ///
  /// 地址由 ApiClient 把服务端返回的相对路径解析到 API base 上。
  Future<String?> requestTranscode(SongEntity song) async {
    final String? url = await ApiClient.instance.requestTranscode(song.guid);
    return ApiClient.instance.resolvePlayUrl(url);
  }

  /// 通知服务端停止一次转码会话（幂等；切歌/停止时由 PlayerService 调用）。
  Future<void> quitTranscode(String guid) =>
      ApiClient.instance.quitTranscode(guid);
}
