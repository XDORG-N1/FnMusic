import 'dart:convert';

import '../services/feiniu/api_models.dart';

/// 统一歌曲模型：由 FNOS API 的 [FnTrack] 转换而来，
/// 服务播放器、列表 UI、歌词、队列等全部模块。
class SongEntity {
  const SongEntity({
    required this.guid,
    required this.title,
    this.artistDisplay,
    this.albumDisplay,
    this.artistGuids = const <String>[],
    this.albumGuid,
    this.coverId,
    this.durationMs,
    this.format,
    this.codec,
    this.bitrate,
    this.sampleRate,
    this.isFavorite = false,
    this.hasLyric = false,
    this.trackNo,
    this.discNo,
    this.isCue = false,
    this.cueOffsetMs,
  });

  final String guid;
  final String title;
  final String? artistDisplay;
  final String? albumDisplay;
  final List<String> artistGuids;
  final String? albumGuid;
  final String? coverId;
  final int? durationMs;
  final String? format;
  final String? codec;
  final int? bitrate;
  final int? sampleRate;
  final bool isFavorite;
  final bool hasLyric;
  final int? trackNo;
  final int? discNo;

  /// CUE 整轨曲目：共享同一物理文件。
  final bool isCue;

  /// CUE 整轨曲目在物理文件内的起始偏移（毫秒，专辑上下文累计）。
  final int? cueOffsetMs;

  String get durationDisplay {
    final int? ms = durationMs;
    if (ms == null) return '--:--';
    final int totalSeconds = (ms / 1000).round();
    final int m = totalSeconds ~/ 60;
    final int s = totalSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// 音频规格展示（如 "FLAC · 1411kbps"）。
  String get audioSpecDisplay {
    final String? f = format;
    if (f == null) return '';
    final int? b = bitrate;
    return b != null ? '$f · ${b}kbps' : f.toUpperCase();
  }

  SongEntity copyWith({
    bool? isFavorite,
    bool? hasLyric,
    bool? isCue,
    int? cueOffsetMs,
  }) {
    return SongEntity(
      guid: guid,
      title: title,
      artistDisplay: artistDisplay,
      albumDisplay: albumDisplay,
      artistGuids: artistGuids,
      albumGuid: albumGuid,
      coverId: coverId,
      durationMs: durationMs,
      format: format,
      codec: codec,
      bitrate: bitrate,
      sampleRate: sampleRate,
      isFavorite: isFavorite ?? this.isFavorite,
      hasLyric: hasLyric ?? this.hasLyric,
      trackNo: trackNo,
      discNo: discNo,
      isCue: isCue ?? this.isCue,
      cueOffsetMs: cueOffsetMs ?? this.cueOffsetMs,
    );
  }

  /// 从 FNOS 曲目模型转换。
  factory SongEntity.fromTrack(FnTrack track) {
    return SongEntity(
      guid: track.guid,
      title: track.title,
      artistDisplay: track.artists
          .map((FnArtist a) => a.name)
          .join(' / '),
      albumDisplay: track.album?.name,
      artistGuids: track.artists.map((FnArtist a) => a.guid).toList(),
      albumGuid: track.album?.guid,
      coverId: track.coverId ?? track.album?.coverId,
      durationMs: track.duration,
      format: track.audioSpec?.format,
      codec: track.audioSpec?.codec,
      bitrate: track.audioSpec?.bitrate,
      sampleRate: track.audioSpec?.sampleRate,
      isFavorite: track.isFavorite,
      hasLyric: track.hasLyric,
      trackNo: track.trackNo,
      discNo: track.discNo,
      isCue: track.isCue,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'guid': guid,
        'title': title,
        'artistDisplay': artistDisplay,
        'albumDisplay': albumDisplay,
        'artistGuids': artistGuids,
        'albumGuid': albumGuid,
        'coverId': coverId,
        'durationMs': durationMs,
        'format': format,
        'codec': codec,
        'bitrate': bitrate,
        'sampleRate': sampleRate,
        'isFavorite': isFavorite,
        'hasLyric': hasLyric,
        'trackNo': trackNo,
        'discNo': discNo,
        'isCue': isCue,
        'cueOffsetMs': cueOffsetMs,
      };

  factory SongEntity.fromJson(Map<String, Object?> json) {
    return SongEntity(
      guid: json['guid'] as String? ?? '',
      title: json['title'] as String? ?? '',
      artistDisplay: json['artistDisplay'] as String?,
      albumDisplay: json['albumDisplay'] as String?,
      artistGuids: (json['artistGuids'] as List<Object?>?)
              ?.whereType<String>()
              .toList() ??
          const <String>[],
      albumGuid: json['albumGuid'] as String?,
      coverId: json['coverId'] as String?,
      durationMs: (json['durationMs'] as num?)?.toInt(),
      format: json['format'] as String?,
      codec: json['codec'] as String?,
      bitrate: (json['bitrate'] as num?)?.toInt(),
      sampleRate: (json['sampleRate'] as num?)?.toInt(),
      isFavorite: json['isFavorite'] as bool? ?? false,
      hasLyric: json['hasLyric'] as bool? ?? false,
      trackNo: (json['trackNo'] as num?)?.toInt(),
      discNo: (json['discNo'] as num?)?.toInt(),
      isCue: json['isCue'] as bool? ?? false,
      cueOffsetMs: (json['cueOffsetMs'] as num?)?.toInt(),
    );
  }

  String encode() => jsonEncode(toJson());

  static SongEntity? decode(String raw) {
    try {
      final Object? json = jsonDecode(raw);
      if (json is Map<Object?, Object?>) {
        return SongEntity.fromJson(json.cast<String, Object?>());
      }
    } catch (_) {}
    return null;
  }
}
