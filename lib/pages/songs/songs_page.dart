import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/list/media_list_tile.dart';
import '../../components/playlist/track_actions_menu.dart';
import '../player/player_route.dart';

/// 全部歌曲：分页加载 + 自然排序。
class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  static const String route = '/library/songs';

  @override
  State<SongsPage> createState() => _SongsPageState();
}

enum _SortMode { title, artist, duration }

class _SongsPageState extends State<SongsPage> {
  final List<SongEntity> _songs = <SongEntity>[];
  final ScrollController _scrollController = ScrollController();
  _SortMode _sort = _SortMode.title;
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 400) {
      _loadMore();
    }
  }

  /// 点按歌曲：以当前排序结果作为队列，从该曲开始播放并进入播放器。
  Future<void> _playAt(int index) async {
    final List<SongEntity> songs = _sorted;
    if (songs.isEmpty) return;
    await FnPlayerService.instance.setQueue(songs, index: index);
    await FnPlayerService.instance.play();
    if (!mounted) return;
    openPlayerPage(context);
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final ApiPage<FnTrack> page =
          await FnTrackService.instance.fetchTracks(page: _page);
      if (!mounted) return;
      setState(() {
        _songs.addAll(page.list.map(SongEntity.fromTrack));
        _hasMore = page.hasMore;
        _page++;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<SongEntity> get _sorted {
    final List<SongEntity> list = List<SongEntity>.from(_songs);
    switch (_sort) {
      case _SortMode.title:
        list.sort((SongEntity a, SongEntity b) =>
            NaturalSort.compare(a.title, b.title));
      case _SortMode.artist:
        list.sort((SongEntity a, SongEntity b) =>
            NaturalSort.compare(a.artistDisplay ?? '', b.artistDisplay ?? ''));
      case _SortMode.duration:
        list.sort((SongEntity a, SongEntity b) =>
            (a.durationMs ?? 0).compareTo(b.durationMs ?? 0));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部歌曲'),
        actions: <Widget>[
          PopupMenuButton<_SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: '排序',
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => const <PopupMenuEntry<_SortMode>>[
              PopupMenuItem<_SortMode>(value: _SortMode.title, child: Text('按标题')),
              PopupMenuItem<_SortMode>(value: _SortMode.artist, child: Text('按歌手')),
              PopupMenuItem<_SortMode>(value: _SortMode.duration, child: Text('按时长')),
            ],
          ),
        ],
      ),
      body: _songs.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              controller: _scrollController,
              itemCount: _sorted.length + 1,
              itemBuilder: (context, index) {
                if (index >= _sorted.length) {
                  return _buildFooter(scheme);
                }
                final SongEntity song = _sorted[index];
                return MediaListTile(
                  imageUrl: ApiClient.instance
                      .coverUrl(song.coverId ?? song.albumGuid),
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
                      TrackActionsMenu(track: song),
                    ],
                  ),
                  onTap: () => _playAt(index),
                );
              },
            ),
    );
  }

  Widget _buildFooter(ColorScheme scheme) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Text(_error!, style: TextStyle(color: scheme.error), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loadMore, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('共 ${_songs.length} 首', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return const SizedBox(height: 60);
  }
}
