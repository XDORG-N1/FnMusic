import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/state/player_state.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/list/media_list_tile.dart';
import '../../components/list/sort_sheet.dart';
import '../../components/playlist/track_actions_menu.dart';
import '../player/player_route.dart';

/// 网页版 /music/genres 的渐变卡片配色（[color, 近黑]），按索引循环。
const List<List<Color>> _genreGradients = <List<Color>>[
  <Color>[Color(0xFFFF3900), Color(0xFF0F0F0F)], // 红
  <Color>[Color(0xFFFF903B), Color(0xFF0F0F0F)], // 橙
  <Color>[Color(0xFF0062FF), Color(0xFF0F0F0F)], // 蓝
  <Color>[Color(0xFF9500FF), Color(0xFF0F0F0F)], // 紫
];

/// 渐变变体（按索引循环，与网页 `index % 4` 一致）。
List<Color> _gradientFor(int index) =>
    _genreGradients[index % _genreGradients.length];

/// 渐变变体（按 guid 哈希派生，详情页与列表保持同一风格色）。
int _gradientVariantFor(String guid) {
  if (guid.isEmpty) return 0;
  final int sum = guid.codeUnits.fold<int>(0, (int acc, int c) => acc + c);
  return sum % _genreGradients.length;
}

/// 风格曲目排序：歌曲名称 / 歌手名称 / 歌曲时长。
List<SongEntity> sortGenreSongs(
  Iterable<SongEntity> songs, {
  required String sortKey,
  required bool ascending,
}) {
  final List<SongEntity> sorted = songs.toList();
  int compare(SongEntity a, SongEntity b) {
    switch (sortKey) {
      case 'artist':
        return NaturalSort.compare(a.artistDisplay ?? '', b.artistDisplay ?? '');
      case 'duration':
        return (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
      default: // title：歌曲名称。
        return NaturalSort.compare(a.title, b.title);
    }
  }

  sorted.sort((SongEntity a, SongEntity b) =>
      ascending ? compare(a, b) : compare(b, a));
  return sorted;
}

/// 风格浏览（列表），仿网页 /music/genres：渐变卡片 + 名称 + 曲目数。
class GenresPage extends StatefulWidget {
  const GenresPage({super.key});

  static const String route = '/library/genres';

  @override
  State<GenresPage> createState() => _GenresPageState();
}

class _GenresPageState extends State<GenresPage> {
  List<FnGenre> _genres = <FnGenre>[];
  bool _loading = true;
  String? _error;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<FnGenre> genres = await FnGenreService.instance.fetchGenres();
      if (!mounted) return;
      setState(() {
        _genres = genres;
        _error = null;
        _errorDetail = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.friendlyMessage
            : '加载失败，请检查网络后重试';
        _errorDetail = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('风格')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: _genres.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final FnGenre genre = _genres[index];
                    return _GenreCard(
                      genre: genre,
                      variantIndex: index,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<dynamic>(
                          builder: (_) => GenreDetailPage(
                            genreGuid: genre.guid,
                            genreName: genre.name,
                            trackCount: genre.trackCount,
                            coverId: genre.coverId,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  /// 错误态：友好提示 + 原始详情 + 重试。
  Widget _buildError(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.category_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_errorDetail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _errorDetail!,
                style: TextStyle(fontSize: 12, color: scheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 风格卡片：渐变底 + 名称 + 曲目数 + 右侧装饰圆形封面（仿网页 120px 卡片）。
class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.genre,
    required this.variantIndex,
    required this.onTap,
  });

  final FnGenre genre;
  final int variantIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String? cover = ApiClient.instance.coverUrl(genre.coverId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _gradientFor(variantIndex),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: <Widget>[
                // 名称 + 曲目数（左侧，避开右侧装饰封面）。
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 110, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        genre.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '共 ${genre.trackCount} 首',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                // 装饰圆形封面（右缘，半透明）。
                Positioned(
                  right: -20,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Opacity(
                      opacity: 0.35,
                      child: ClipOval(
                        child: ArtworkWidget(
                          imageUrl: cover,
                          size: 120,
                          placeholderText: genre.name,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 风格详情：渐变 Hero（名称 + 曲目数 + 播放全部）+ 曲目列表，仿网页。
class GenreDetailPage extends StatefulWidget {
  const GenreDetailPage({
    super.key,
    required this.genreGuid,
    required this.genreName,
    this.trackCount,
    this.coverId,
  });

  final String genreGuid;
  final String genreName;

  /// 风格下曲目总数（来自列表接口，缺失时回退已加载曲目数）。
  final int? trackCount;
  final String? coverId;

  @override
  State<GenreDetailPage> createState() => _GenreDetailPageState();
}

class _GenreDetailPageState extends State<GenreDetailPage> {
  List<SongEntity> _tracks = <SongEntity>[];
  bool _loading = true;
  String? _error;
  String? _errorDetail;
  String _sortKey = 'title';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<FnTrack> tracks =
          await FnGenreService.instance.fetchGenreTracks(widget.genreGuid);
      if (!mounted) return;
      setState(() {
        _tracks = sortGenreSongs(
          tracks.map(SongEntity.fromTrack),
          sortKey: _sortKey,
          ascending: _sortAscending,
        );
        _error = null;
        _errorDetail = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException
            ? e.friendlyMessage
            : '加载失败，请检查网络后重试';
        _errorDetail = '$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortTracks() {
    setState(() {
      _tracks = sortGenreSongs(
        _tracks,
        sortKey: _sortKey,
        ascending: _sortAscending,
      );
    });
  }

  void _showSortSheet() {
    showSortSheet(
      context,
      SortSheet(
        title: '排序',
        options: const <SortOption>[
          SortOption(key: 'title', label: '歌曲名称', icon: Icons.sort_by_alpha),
          SortOption(key: 'artist', label: '歌手名称', icon: Icons.person_outline),
          SortOption(key: 'duration', label: '歌曲时长', icon: Icons.schedule),
        ],
        currentKey: _sortKey,
        ascending: _sortAscending,
        onSelectKey: (String value) {
          _sortKey = value;
          _sortTracks();
        },
        onSelectAscending: (bool value) {
          _sortAscending = value;
          _sortTracks();
        },
      ),
    );
  }

  /// 曲目总数：优先列表接口的 trackCount，缺失时用已加载曲目数。
  int get _songCount {
    final int? declared = widget.trackCount;
    if (declared != null && declared > 0) return declared;
    return _tracks.length;
  }

  void _playQueue(int index) {
    if (_tracks.isEmpty) return;
    unawaited(FnPlayerService.instance
        .setQueue(_tracks, index: index)
        .then((_) => FnPlayerService.instance.play())
        .then((_) {
      if (mounted) openPlayerPage(context);
    }));
  }

  void _playAll() => _playQueue(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.genreName),
        actions: <Widget>[
          SortActionButton(onTap: _showSortSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context)
              : ListView.builder(
                  itemCount: _tracks.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildHeader(context);
                    final SongEntity song = _tracks[index - 1];
                    return ValueListenableBuilder<SongEntity?>(
                      valueListenable: AppPlayerState.instance.currentSong,
                      builder: (context, current, _) {
                        final bool isCurrent = current?.guid == song.guid;
                        return MediaListTile(
                          imageUrl: ApiClient.instance.coverUrl(song.coverId),
                          title: song.title,
                          subtitle: song.artistDisplay,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(song.durationDisplay),
                              TrackActionsMenu(track: song),
                            ],
                          ),
                          selected: isCurrent,
                          onTap: () => _playQueue(index - 1),
                        );
                      },
                    );
                  },
                ),
    );
  }

  /// 仿网页 /music/genres 详情头部：渐变 Hero + 名称 + 共 N 首 + 播放全部 +
  /// 右侧装饰圆形封面。
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientFor(_gradientVariantFor(widget.genreGuid)),
        ),
      ),
      child: Stack(
        children: <Widget>[
          // 文字 + 操作（左侧，避开右侧装饰封面）。
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 150, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Spacer(),
                Text(
                  widget.genreName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '共 $_songCount 首',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _tracks.isEmpty ? null : _playAll,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放全部'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          // 装饰圆形封面（右缘，半透明）。
          Positioned(
            right: -24,
            bottom: -24,
            child: Opacity(
              opacity: 0.35,
              child: ClipOval(
                child: ArtworkWidget(
                  imageUrl: ApiClient.instance.coverUrl(widget.coverId),
                  size: 180,
                  placeholderText: widget.genreName,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 错误态：友好提示 + 原始详情 + 重试。
  Widget _buildError(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.music_off_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (_errorDetail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _errorDetail!,
                style: TextStyle(fontSize: 12, color: scheme.outline),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
