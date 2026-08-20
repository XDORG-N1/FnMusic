import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../state/song_state.dart';
import '../feiniu/api_client.dart';

class LyricsRepository {
  /// 加载歌词，优先从缓存读取，未命中则从 API 获取
  Future<String?> loadLrc(SongEntity song) async {
    // 1. 读取本地缓存
    final cached = await _readFromCache(song.guid);
    if (cached != null && cached.trim().isNotEmpty) {
      return cached;
    }

    // 2. 从 API 获取
    try {
      final lyricText = await ApiClient.instance.getLyricText(song.guid);
      if (lyricText != null && lyricText.trim().isNotEmpty) {
        await _writeToCache(song.guid, lyricText);
        return lyricText;
      }
    } catch (_) {
      // API 返回失败时静默处理
    }

    return null;
  }

  Future<void> removeCachedLrc(String songGuid) async {
    try {
      final file = await _cacheFileForSongId(songGuid);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> saveLrcToCache(
    String songGuid,
    String content, {
    bool overwrite = false,
  }) async {
    final c = content.replaceFirst('﻿', '').trim();
    if (c.isEmpty) return;
    if (!overwrite) {
      final exists = await hasCachedLrc(songGuid);
      if (exists) return;
    }
    await _writeToCache(songGuid, c);
  }

  Future<bool> hasCachedLrc(String songGuid) async {
    try {
      final file = await _cacheFileForSongId(songGuid);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  Future<String?> loadCachedLrc(String songGuid) async {
    return _readFromCache(songGuid);
  }

  Future<String?> _readFromCache(String songId) async {
    try {
      final file = await _cacheFileForSongId(songId);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeToCache(String songId, String content) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final lyricsDir = Directory(p.join(dir.path, 'lyrics'));
      if (!await lyricsDir.exists()) {
        await lyricsDir.create(recursive: true);
      }
      final file = File(p.join(lyricsDir.path, '${_cacheKey(songId)}.lrc'));
      await file.writeAsString(content, flush: true);
    } catch (_) {}
  }

  Future<File> _cacheFileForSongId(String songId) async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'lyrics', '${_cacheKey(songId)}.lrc'));
  }

  /// FNV-1a 64 位散列，避免曲目 guid 直接落在文件名里。
  String _cacheKey(String songId) {
    final bytes = utf8.encode(songId);
    const int offsetBasis = 0xcbf29ce484222325;
    const int prime = 0x100000001b3;
    const int mask64 = 0xFFFFFFFFFFFFFFFF;
    var hash = offsetBasis;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * prime) & mask64;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
