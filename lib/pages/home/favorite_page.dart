import 'package:flutter/material.dart';

import '../../app/services/feiniu/api_client.dart';
import '../../app/services/feiniu/favorite_service.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/list/media_list_tile.dart';

/// 收藏页（简化移植）：服务端收藏歌曲列表，点按播放队列、长按取消收藏。
class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  static const String route = '/home/favorites';

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  List<SongEntity>? _songs;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks =
          await FeiNiuFavoriteService.instance.fetchFavoriteTracks();
      if (!mounted) return;
      setState(() {
        _songs = tracks.map(SongEntity.fromTrack).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _playAt(int index) async {
    final List<SongEntity>? songs = _songs;
    if (songs == null || songs.isEmpty) return;
    await FnPlayerService.instance.setQueue(songs, index: index);
    await FnPlayerService.instance.play();
  }

  Future<void> _shufflePlay() async {
    final List<SongEntity>? songs = _songs;
    if (songs == null || songs.isEmpty) return;
    await FnPlayerService.instance.setQueue(
      songs,
      index: songs.length > 1
          ? _randomIndex(songs.length)
          : 0,
    );
    await FnPlayerService.instance.play();
  }

  Future<void> _unfavorite(SongEntity song) async {
    final bool confirmed = await _confirmUnfavorite(song);
    if (!confirmed || !mounted) return;
    try {
      await FeiNiuFavoriteService.instance.unfavorite(song.guid);
      if (!mounted) return;
      setState(() => _songs?.removeWhere((SongEntity s) => s.guid == song.guid));
      _toast('已取消收藏：${song.title}');
    } catch (e) {
      if (!mounted) return;
      _toast('取消收藏失败：$e');
    }
  }

  Future<bool> _confirmUnfavorite(SongEntity song) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text('确定将「${song.title}」移出收藏吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移出'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  int _randomIndex(int length) {
    return DateTime.now().millisecondsSinceEpoch % length;
  }

  @override
  Widget build(BuildContext context) {
    final List<SongEntity>? songs = _songs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('收藏'),
        actions: <Widget>[
          if (songs != null && songs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: '随机播放',
              onPressed: _shufflePlay,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.cloud_off,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('收藏加载失败', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('请检查网络后重试'),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final List<SongEntity> songs = _songs ?? const <SongEntity>[];
    if (songs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            const SizedBox(height: 160),
            Center(
              child: Column(
                children: <Widget>[
                  Icon(Icons.favorite_border,
                      size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('还没有收藏', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '在播放页或列表中点击收藏，歌曲会出现在这里',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: songs.length,
        itemBuilder: (BuildContext context, int index) {
          final SongEntity song = songs[index];
          return MediaListTile(
            imageUrl: ApiClient.instance.coverUrl(song.coverId),
            title: song.title,
            subtitle: song.artistDisplay,
            onTap: () => _playAt(index),
            onLongPress: () => _unfavorite(song),
          );
        },
      ),
    );
  }
}
