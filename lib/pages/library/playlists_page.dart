import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/state/player_state.dart';
import '../../app/state/song_state.dart';
import '../../app/services/stats_service.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/list/media_list_tile.dart';
import '../../components/playlist/track_actions_menu.dart';
import '../player/player_route.dart';

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
                                playlistCoverId: playlist.coverId,
                                playlistTrackCount: playlist.trackCount,
                              ),
                            ),
                          ),
                          onLongPress: () => _showPlaylistMenu(playlist),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) =>
                                      ArtworkWidget(
                                    imageUrl: ApiClient.instance
                                        .coverUrl(playlist.coverId),
                                    size: constraints.maxWidth,
                                    borderRadius: BorderRadius.circular(14),
                                    placeholderIcon: Icons.queue_music,
                                  ),
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

/// 歌单详情：仿网页版 hero（封面 + 歌单名 + 共 N 首 + 播放全部/随机播放）
/// +「歌曲」分节 + 曲目行（更多菜单：加入歌单 / 从歌单移除 / 下一首 / 队列 / 收藏…）。
class PlaylistDetailPage extends StatefulWidget {
  const PlaylistDetailPage({
    super.key,
    required this.playlistGuid,
    this.playlistName,
    this.playlistCoverId,
    this.playlistTrackCount,
  });

  final String playlistGuid;
  final String? playlistName;
  final String? playlistCoverId;
  final int? playlistTrackCount;

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
    if (!mounted) return;
    openPlayerPage(context);
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
    if (!mounted) return;
    openPlayerPage(context);
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

  String get _displayName {
    final String? name = widget.playlistName?.trim();
    return (name == null || name.isEmpty) ? '歌单' : name;
  }

  /// 仿 FNOS 网页版歌单头部：大封面 +「歌单」kicker + 名称 + 共 N 首 +
  /// 播放全部 / 随机播放操作。
  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final int count = widget.playlistTrackCount ?? _tracks.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ArtworkWidget(
            imageUrl: ApiClient.instance.coverUrl(widget.playlistCoverId),
            size: 160,
            borderRadius: BorderRadius.circular(24),
            placeholderText: _displayName,
          ),
          const SizedBox(height: 16),
          Text(
            '歌单',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 2.4,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '共 $count 首',
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          // 操作行：播放全部（主按钮）+ 随机播放。
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _tracks.isEmpty ? null : () => _playAt(0),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('播放全部'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.shuffle),
                tooltip: '随机播放',
                visualDensity: VisualDensity.compact,
                onPressed: _tracks.isEmpty ? null : _shufflePlay,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_displayName)),
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
                          style: theme.textTheme.bodyMedium),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 48),
                      children: <Widget>[
                        _buildHeader(context),
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          endIndent: 16,
                          color: Colors.grey.withValues(alpha: 0.2),
                        ),
                        // 歌曲区标题（播放操作已在头部）。
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            '歌曲',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        ..._tracks.asMap().entries.map(
                              (MapEntry<int, SongEntity> entry) =>
                                  _buildTrackRow(entry.key, entry.value),
                            ),
                      ],
                    ),
    );
  }

  Widget _buildTrackRow(int index, SongEntity song) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<SongEntity?>(
      valueListenable: AppPlayerState.instance.currentSong,
      builder: (context, current, _) {
        final bool isCurrent = current?.guid == song.guid;
        return MediaListTile(
          imageUrl: ApiClient.instance.coverUrl(song.coverId),
          title: song.title,
          subtitle: song.artistDisplay,
          selected: isCurrent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                song.durationDisplay,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
              TrackActionsMenu(
                track: song,
                showRemoveFromPlaylist: true,
                onRemoveFromPlaylist: () => _removeTrack(song),
              ),
            ],
          ),
          onTap: () => _playAt(index),
        );
      },
    );
  }
}
