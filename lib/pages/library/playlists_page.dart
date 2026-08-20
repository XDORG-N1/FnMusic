import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/services/stats_service.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/list/media_list_tile.dart';

/// 歌单浏览（网格）。
class PlaylistsPage extends StatefulWidget {
  const PlaylistsPage({super.key});

  static const String route = '/library/playlists';

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  List<FnPlaylist> _playlists = <FnPlaylist>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<FnPlaylist> playlists =
          await FnPlaylistService.instance.fetchPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rename(FnPlaylist playlist) async {
    final TextEditingController controller =
        TextEditingController(text: playlist.name);
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == playlist.name) return;
    try {
      await FnPlaylistService.instance.renamePlaylist(playlist.guid, name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重命名失败：$e')));
      }
    }
  }

  Future<void> _delete(FnPlaylist playlist) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除歌单「${playlist.name}」吗？此操作不可恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FnPlaylistService.instance.deletePlaylist(playlist.guid);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  Future<void> _showPlaylistMenu(FnPlaylist playlist) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                playlist.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.of(context).pop();
                _rename(playlist);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                '删除',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _delete(playlist);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await FnPlaylistService.instance.createPlaylist(name);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('歌单'),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.add), tooltip: '新建歌单', onPressed: _create),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(_error!),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : _playlists.isEmpty
                  ? Center(
                      child: Text('暂无歌单', style: Theme.of(context).textTheme.bodyMedium),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: _playlists.length,
                      itemBuilder: (context, index) {
                        final FnPlaylist playlist = _playlists[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<dynamic>(
                              builder: (_) => PlaylistDetailPage(
                                playlistGuid: playlist.guid,
                                playlistName: playlist.name,
                              ),
                            ),
                          ),
                          onLongPress: () => _showPlaylistMenu(playlist),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: ArtworkWidget(
                                  imageUrl: null,
                                  size: double.infinity,
                                  borderRadius: BorderRadius.circular(14),
                                  placeholderIcon: Icons.queue_music,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                '${playlist.trackCount ?? 0} 首',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}

/// 歌单详情：列表播放 / 随机播放 / 移出曲目。
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistGuid,
    this.playlistName,
  });

  final String playlistGuid;
  final String? playlistName;

  @override
  State<PlaylistDetailPage> createState() => _PlaylistDetailPageState();
}

class _PlaylistDetailPageState extends State<PlaylistDetailPage> {
  List<SongEntity> _tracks = <SongEntity>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<FnTrack> tracks =
          await FnPlaylistService.instance.fetchPlaylistTracks(widget.playlistGuid);
      if (!mounted) return;
      setState(() {
        _tracks = tracks.map(SongEntity.fromTrack).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playAt(int index) async {
    final List<SongEntity> tracks = _tracks;
    if (tracks.isEmpty) return;
    await FnPlayerService.instance.setQueue(tracks, index: index);
    await FnPlayerService.instance.play();
    _recordPlay();
  }

  Future<void> _shufflePlay() async {
    final List<SongEntity> tracks = _tracks;
    if (tracks.isEmpty) return;
    await FnPlayerService.instance.setQueue(
      tracks,
      index: tracks.length > 1 ? _randomIndex(tracks.length) : 0,
    );
    await FnPlayerService.instance.play();
    _recordPlay();
  }

  void _recordPlay() {
    unawaited(StatsService.instance.recordPlaylistPlay(
      playlistId: widget.playlistGuid,
      playlistTitle: widget.playlistName ?? '',
    ));
  }

  Future<void> _removeTrack(SongEntity song) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('移出歌单'),
        content: Text('确定将「${song.title}」移出该歌单吗？'),
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
      await FnPlaylistService.instance
          .removeTrack(widget.playlistGuid, song.guid);
      if (!mounted) return;
      setState(() => _tracks.removeWhere((SongEntity s) => s.guid == song.guid));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已移出：${song.title}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('移出失败：$e')));
    }
  }

  int _randomIndex(int length) {
    return DateTime.now().millisecondsSinceEpoch % length;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool hasTracks = _tracks.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName ?? '歌单'),
        actions: <Widget>[
          if (hasTracks)
            IconButton(
              icon: const Icon(Icons.playlist_play),
              tooltip: '播放全部',
              onPressed: () => _playAt(0),
            ),
          if (hasTracks)
            IconButton(
              icon: const Icon(Icons.shuffle),
              tooltip: '随机播放',
              onPressed: _shufflePlay,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(_error!),
                      const SizedBox(height: 8),
                      OutlinedButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : _tracks.isEmpty
                  ? Center(
                      child: Text('歌单暂无歌曲',
                          style: Theme.of(context).textTheme.bodyMedium),
                    )
                  : ListView.builder(
                      itemCount: _tracks.length,
                      itemBuilder: (context, index) {
                        final SongEntity song = _tracks[index];
                        return MediaListTile(
                          imageUrl: ApiClient.instance.coverUrl(song.coverId),
                          title: song.title,
                          subtitle: song.artistDisplay,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                song.durationDisplay,
                                style: TextStyle(
                                    color: scheme.onSurfaceVariant, fontSize: 13),
                              ),
                              PopupMenuButton<String>(
                                tooltip: '更多',
                                icon: const Icon(Icons.more_vert),
                                onSelected: (String value) {
                                  if (value == 'remove') _removeTrack(song);
                                },
                                itemBuilder: (BuildContext context) =>
                                    const <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'remove',
                                    child: ListTile(
                                      leading: Icon(Icons.remove_circle_outline),
                                      title: Text('移出歌单'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _playAt(index),
                        );
                      },
                    ),
    );
  }
}
