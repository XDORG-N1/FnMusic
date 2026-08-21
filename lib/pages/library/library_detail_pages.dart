import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/state/player_state.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/list/media_list_tile.dart';
import '../../components/list/sort_sheet.dart';

/// 主歌手标签：`'A / B'` → `'A 等'`；单歌手原样；空 → `'未知歌手'`。
String primaryArtistLabel(String? artistDisplay) {
  final String text = artistDisplay?.trim() ?? '';
  if (text.isEmpty) return '未知歌手';
  final List<String> parts = text
      .split(RegExp(r'[/、,，;；&]'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
  return parts.length <= 1 ? text : '${parts.first} 等';
}

/// 专辑曲目排序：轨道号 / 歌曲名称 / 歌手名称 / 歌曲时长。
List<SongEntity> sortAlbumDetailSongs(
  Iterable<SongEntity> songs, {
  required String sortKey,
  required bool ascending,
}) {
  final List<SongEntity> sorted = songs.toList();
  int compare(SongEntity a, SongEntity b) {
    switch (sortKey) {
      case 'title':
        return NaturalSort.compare(a.title, b.title);
      case 'artist':
        return NaturalSort.compare(
            a.artistDisplay ?? '', b.artistDisplay ?? '');
      case 'duration':
        return (a.durationMs ?? 0).compareTo(b.durationMs ?? 0);
      default: // trackNumber：碟号优先，再按轨道号。
        final int disc1 = a.discNo ?? 1;
        final int disc2 = b.discNo ?? 1;
        if (disc1 != disc2) return disc1.compareTo(disc2);
        return (a.trackNo ?? 1 << 30).compareTo(b.trackNo ?? 1 << 30);
    }
  }

  sorted.sort((SongEntity a, SongEntity b) =>
      ascending ? compare(a, b) : compare(b, a));
  return sorted;
}

/// 专辑详情：头部信息 + 曲目列表 + 参与创作的歌手。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({
    super.key,
    required this.albumGuid,
    this.albumName,
    this.albumCoverId,
    this.albumYear,
  });

  final String albumGuid;
  final String? albumName;
  final String? albumCoverId;
  final int? albumYear;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  List<FnTrack> _rawTracks = <FnTrack>[];
  List<SongEntity> _tracks = <SongEntity>[];
  bool _loading = true;
  String? _error;

  bool _showCovers = true;
  String _sortKey = 'trackNumber';
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
          await FnAlbumService.instance.fetchAlbumTracks(widget.albumGuid);
      if (!mounted) return;
      setState(() {
        // CUE 整轨：按镜像累计起始偏移（专辑上下文零额外网络）。
        final List<SongEntity> songs = FnCueService.instance.withCueOffsets(
          tracks.map(SongEntity.fromTrack).toList(),
          tracks,
        );
        _rawTracks = tracks;
        _tracks = sortAlbumDetailSongs(
          songs,
          sortKey: _sortKey,
          ascending: _sortAscending,
        );
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _sortTracks() {
    setState(() {
      _tracks = sortAlbumDetailSongs(
        _tracks,
        sortKey: _sortKey,
        ascending: _sortAscending,
      );
    });
  }

  /// 专辑展示名：优先显式传入，其次首曲的专辑名。
  String get _displayName {
    if (widget.albumName?.trim().isNotEmpty == true) {
      return widget.albumName!.trim();
    }
    if (_rawTracks.isNotEmpty) {
      final String? albumName = _rawTracks.first.album?.name;
      if (albumName != null && albumName.isNotEmpty) return albumName;
    }
    return '专辑';
  }

  void _showMoreSheet() {
    showSortSheet(
      context,
      SortSheet(
        title: '更多',
        options: const <SortOption>[
          SortOption(
            key: 'trackNumber',
            label: '轨道号',
            icon: Icons.format_list_numbered_rounded,
          ),
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
        extra: SwitchListTile(
          title: const Text('显示专辑封面'),
          subtitle: const Text('关闭时显示歌曲序号'),
          secondary: const Icon(Icons.image_outlined),
          value: _showCovers,
          onChanged: (bool value) => setState(() => _showCovers = value),
        ),
      ),
    );
  }

  void _playQueue(List<SongEntity> songs, int index) {
    if (songs.isEmpty) return;
    FnPlayerService.instance
        .setQueue(songs, index: index)
        .then((_) => FnPlayerService.instance.play());
  }

  void _shufflePlay() {
    if (_tracks.isEmpty) return;
    final List<SongEntity> shuffled = List<SongEntity>.of(_tracks)..shuffle();
    _playQueue(shuffled, 0);
  }

  void _orderPlay() => _playQueue(_tracks, 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onPressed: _showMoreSheet,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final FnTrack? rep = _rawTracks.isNotEmpty ? _rawTracks.first : null;

    final String artistLabel = primaryArtistLabel(
      rep?.artists.map((FnArtist a) => a.name).join(' / '),
    );
    final int? year = widget.albumYear ?? rep?.year;
    final String infoText = '${_tracks.length}首${year != null ? ' · $year' : ''}';
    final String? headerCover =
        widget.albumCoverId ?? rep?.album?.coverId ?? rep?.coverId;

    final List<FnArtist> artists = _participatingArtists();

    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: <Widget>[
        // 专辑头部：封面 + 名称 + 歌手 + 曲数/年份。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ArtworkWidget(
                imageUrl: ApiClient.instance.coverUrl(headerCover),
                size: 110,
                borderRadius: BorderRadius.circular(12),
                placeholderText: _displayName,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      artistLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.textTheme.bodyMedium?.color
                            ?.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      infoText,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          thickness: 0.5,
          indent: 16,
          endIndent: 16,
          color: Colors.grey.withValues(alpha: 0.2),
        ),
        // 歌曲操作行：随机 / 顺序播放。
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: <Widget>[
              Text(
                '歌曲',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.shuffle),
                tooltip: '随机播放',
                visualDensity: VisualDensity.compact,
                onPressed: _tracks.isEmpty ? null : _shufflePlay,
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: '顺序播放',
                visualDensity: VisualDensity.compact,
                onPressed: _tracks.isEmpty ? null : _orderPlay,
              ),
            ],
          ),
        ),
        // 曲目列表：当前播放行高亮；封面/序号可切换。
        ..._tracks.asMap().entries.map((MapEntry<int, SongEntity> entry) {
          final int index = entry.key;
          final SongEntity song = entry.value;
          return ValueListenableBuilder<SongEntity?>(
            valueListenable: AppPlayerState.instance.currentSong,
            builder: (context, current, _) {
              final bool isCurrent = current?.guid == song.guid;
              return MediaListTile(
                title: song.title,
                subtitle: song.artistDisplay,
                trailing: Text(song.durationDisplay),
                selected: isCurrent,
                leadingWidget: _showCovers
                    ? ArtworkWidget(
                        imageUrl: ApiClient.instance.coverUrl(song.coverId),
                        size: 48,
                        borderRadius: BorderRadius.circular(8),
                        placeholderText: song.title,
                      )
                    : SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                onTap: () => _playQueue(_tracks, index),
              );
            },
          );
        }),
        // 参与创作的歌手。
        if (artists.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Divider(
            height: 1,
            thickness: 0.5,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.withValues(alpha: 0.2),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '参与创作的歌手',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ...artists.map((FnArtist artist) {
            final String? artistCover =
                artist.coverId ?? _coverForArtist(artist);
            return ListTile(
              leading: ClipOval(
                child: ArtworkWidget(
                  imageUrl: ApiClient.instance.coverUrl(artistCover),
                  size: 44,
                  borderRadius: BorderRadius.circular(22),
                  placeholderText: artist.name,
                ),
              ),
              title: Text(artist.name),
              onTap: artist.guid.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<dynamic>(
                          builder: (_) => ArtistDetailPage(
                            artistGuid: artist.guid,
                            artistName: artist.name,
                          ),
                        ),
                      ),
            );
          }),
        ],
      ],
    );
  }

  /// 参与创作的歌手：跨曲目去重（优先 guid），拼音排序。
  List<FnArtist> _participatingArtists() {
    final Map<String, FnArtist> byGuid = <String, FnArtist>{};
    final Map<String, FnArtist> byName = <String, FnArtist>{};
    for (final FnTrack t in _rawTracks) {
      for (final FnArtist a in t.artists) {
        if (a.guid.isNotEmpty) {
          byGuid[a.guid] = a;
        } else if (a.name.isNotEmpty) {
          byName[a.name] = a;
        }
      }
    }
    return <FnArtist>[...byGuid.values, ...byName.values]
      ..sort((FnArtist a, FnArtist b) => NaturalSort.compare(a.name, b.name));
  }

  /// 歌手无独立封面时，回退到该歌手参与的首曲封面。
  String? _coverForArtist(FnArtist artist) {
    for (final FnTrack t in _rawTracks) {
      final bool matched = artist.guid.isNotEmpty
          ? t.artists.any((FnArtist a) => a.guid == artist.guid)
          : t.artists.any((FnArtist a) => a.name == artist.name);
      if (matched) return t.album?.coverId ?? t.coverId;
    }
    return null;
  }
}

/// 歌手详情：曲目列表。
class ArtistDetailPage extends StatefulWidget {
  const ArtistDetailPage({super.key, required this.artistGuid, this.artistName});

  final String artistGuid;
  final String? artistName;

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
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
          await FnArtistService.instance.fetchArtistTracks(widget.artistGuid);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.artistName ?? '歌手')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final SongEntity song = _tracks[index];
                    return MediaListTile(
                      imageUrl: ApiClient.instance.coverUrl(song.coverId),
                      title: song.title,
                      subtitle: song.albumDisplay,
                      trailing: Text(song.durationDisplay),
                      onTap: () {
                        final List<SongEntity> songs = _tracks;
                        if (songs.isEmpty) return;
                        FnPlayerService.instance
                            .setQueue(songs, index: index)
                            .then((_) => FnPlayerService.instance.play());
                      },
                    );
                  },
                ),
    );
  }
}
