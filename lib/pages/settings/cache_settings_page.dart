import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/services/cover_local_cache.dart';
import '../../app/services/player/stream_cache_service.dart';
import '../../app/state/settings_state.dart';

/// 封面图缓存目录（cached_network_image / flutter_cache_manager）。
const String kArtworkCacheDirName = 'libCachedImageData';

/// 缓存管理：封面 / 歌词 / 音乐缓存占用与清理 + 缓存上限。
class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  static const String route = '/settings/cache';

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  int _artworkSize = 0;
  int _lyricsSize = 0;
  int _streamSize = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheSizes();
  }

  Future<void> _loadCacheSizes() async {
    setState(() => _loading = true);
    final int artwork = await _getArtworkCacheSize();
    final int lyrics = await _getLyricsCacheSize();
    final int stream = await StreamCacheService.instance.totalSize();
    if (!mounted) return;
    setState(() {
      _artworkSize = artwork;
      _lyricsSize = lyrics;
      _streamSize = stream;
      _loading = false;
    });
  }

  /// 封面缓存 = 媒体通知封面目录（covers_v2）+ 列表封面（libCachedImageData）。
  Future<int> _getArtworkCacheSize() async {
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final Directory coverDir =
          Directory(p.join(tempDir.path, CoverLocalCache.kDirName));
      final Directory artworkDir =
          Directory(p.join(tempDir.path, kArtworkCacheDirName));
      return await _dirSize(coverDir) + await _dirSize(artworkDir);
    } catch (_) {
      return 0;
    }
  }

  /// 歌词缓存（getApplicationSupportDirectory()/lyrics）。
  Future<int> _getLyricsCacheSize() async {
    try {
      final Directory dir = await getApplicationSupportDirectory();
      return await _dirSize(Directory(p.join(dir.path, 'lyrics')));
    } catch (_) {
      return 0;
    }
  }

  Future<int> _dirSize(Directory dir) async {
    if (!await dir.exists()) return 0;
    int total = 0;
    try {
      await for (final FileSystemEntity f
          in dir.list(recursive: true, followLinks: false)) {
        if (f is File) total += await f.length();
      }
    } catch (_) {}
    return total;
  }

  /// 删除目录内容（保留目录本身，避免后续写缓存报错）。
  Future<void> _clearDirContents(Directory dir) async {
    if (!await dir.exists()) return;
    try {
      await for (final FileSystemEntity e in dir.list(followLinks: false)) {
        await e.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<bool> _confirm(String title, String content) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _clearArtworkCache() async {
    if (!await _confirm('清除封面缓存', '确定要清除封面缓存吗？这将需要重新下载封面。')) {
      return;
    }
    setState(() => _loading = true);
    // 走 CoverLocalCache.clearArtworkCache：用 flutter_cache_manager 官方
    // emptyCache() 同时清索引库与文件，避免直接删目录破坏 SQLite 导致应用异常。
    await CoverLocalCache.clearArtworkCache();
    if (!mounted) return;
    await _loadCacheSizes();
    _toast('封面缓存已清除');
  }

  Future<void> _clearLyricsCache() async {
    if (!await _confirm('清除歌词缓存', '确定要清除歌词缓存吗？本地歌词会在需要时重新获取。')) {
      return;
    }
    setState(() => _loading = true);
    final Directory dir = await getApplicationSupportDirectory();
    await _clearDirContents(Directory(p.join(dir.path, 'lyrics')));
    if (!mounted) return;
    await _loadCacheSizes();
    _toast('歌词缓存已清除');
  }

  Future<void> _clearStreamCache() async {
    if (!await _confirm('清除音乐缓存', '确定要清除已缓存的音乐吗？下次播放需要重新下载。')) {
      return;
    }
    setState(() => _loading = true);
    await StreamCacheService.instance.clear();
    if (!mounted) return;
    await _loadCacheSizes();
    _toast('音乐缓存已清除');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const List<String> suffixes = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i += 1;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  static String _formatGb(int mb) => '${(mb / 1024).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('缓存管理')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _SectionHeader('缓存管理'),
          _CacheTile(
            icon: Icons.image_outlined,
            iconColor: scheme.tertiary,
            title: '封面缓存',
            subtitle: _loading ? '计算中…' : '占用空间：${_formatSize(_artworkSize)}',
            onTap: _loading ? null : _clearArtworkCache,
          ),
          _CacheTile(
            icon: Icons.description_outlined,
            iconColor: scheme.secondary,
            title: '歌词缓存',
            subtitle: _loading ? '计算中…' : '占用空间：${_formatSize(_lyricsSize)}',
            onTap: _loading ? null : _clearLyricsCache,
          ),
          _CacheTile(
            icon: Icons.audiotrack_outlined,
            iconColor: scheme.primary,
            title: '音乐缓存',
            subtitle: _loading
                ? '计算中…'
                : '占用空间：${_formatSize(_streamSize)}'
                    ' / 上限 ${_formatGb(AppCacheSettings.cacheLimitMb.value)}',
            onTap: _loading ? null : _clearStreamCache,
          ),
          _SectionHeader('缓存设置'),
          ValueListenableBuilder<int>(
            valueListenable: AppCacheSettings.cacheLimitMb,
            builder: (BuildContext context, int limitMb, _) {
              return ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('缓存上限'),
                subtitle: Text(
                  '超出上限时自动清理最旧的缓存（${_formatGb(limitMb)}）',
                ),
                trailing: Text(
                  _formatGb(limitMb),
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<int>(
            valueListenable: AppCacheSettings.cacheLimitMb,
            builder: (BuildContext context, int limitMb, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Slider(
                  value: limitMb.clamp(256, 5120).toDouble(),
                  min: 256,
                  max: 5120,
                  divisions: 19,
                  label: _formatGb(limitMb),
                  onChanged: (double v) =>
                      AppCacheSettings.setCacheLimitMb(v.round()),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _CacheTile extends StatelessWidget {
  const _CacheTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(Icons.cleaning_services_outlined,
          color: onTap == null
              ? Theme.of(context).colorScheme.outlineVariant
              : null),
      onTap: onTap,
    );
  }
}
