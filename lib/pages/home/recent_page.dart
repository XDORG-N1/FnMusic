import 'package:flutter/material.dart';

import '../../app/services/feiniu/api_client.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/list/media_list_tile.dart';

/// 最近播放页：服务端播放历史列表，点按播放队列、长按移出历史。
class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  static const String route = '/home/recent';

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
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
      final tracks = await ApiClient.instance.getPlayHistory(page: 1, size: 100);
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
      index: songs.length > 1 ? _randomIndex(songs.length) : 0,
    );
    await FnPlayerService.instance.play();
  }

  Future<void> _removeFromHistory(SongEntity song) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('移出最近播放'),
        content: Text('确定将「${song.title}」从最近播放移除吗？'),
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
    if (confirmed != true || !mounted) return;
    try {
      await ApiClient.instance.postData(
        '/play-history/delete',
        body: <String, Object?>{'trackGUIDs': <String>[song.guid]},
      );
      if (!mounted) return;
      setState(() => _songs?.removeWhere((SongEntity s) => s.guid == song.guid));
    } catch (e) {
      if (!mounted) return;
      _toast('移出失败：$e');
    }
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
        title: const Text('最近播放'),
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
            Text('最近播放加载失败', style: Theme.of(context).textTheme.titleMedium),
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
                  Icon(Icons.history,
                      size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('还没有播放记录', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '听过的歌曲会出现在这里',
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
            onLongPress: () => _removeFromHistory(song),
          );
        },
      ),
    );
  }
}
