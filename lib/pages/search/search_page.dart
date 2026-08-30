import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../components/list/media_list_tile.dart';
import '../../components/playlist/track_actions_menu.dart';
import '../library/library_detail_pages.dart';
import '../player/player_route.dart';

/// 全局搜索（歌曲 / 专辑 / 歌手）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _searched = false;
  bool _loading = false;
  String? _error;

  List<SongEntity> _tracks = <SongEntity>[];
  List<FnAlbum> _albums = <FnAlbum>[];
  List<FnArtist> _artists = <FnArtist>[];

  Future<void> _search() async {
    final String keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searched = true;
      _loading = true;
      _error = null;
    });
    try {
      final ApiPage<FnTrack> trackPage =
          await FnSearchService.instance.searchTracks(keyword);
      final List<SongEntity> tracks = trackPage.list
          .map(SongEntity.fromTrack)
          .toList();
      final ApiPage<FnAlbum> albumPage =
          await FnSearchService.instance.searchAlbums(keyword);
      final ApiPage<FnArtist> artistPage =
          await FnSearchService.instance.searchArtists(keyword);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _albums = albumPage.list;
        _artists = artistPage.list;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: '搜索歌曲、专辑、歌手',
            border: InputBorder.none,
          ),
        ),
        actions: <Widget>[
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_searched) {
      return _buildEmpty('输入关键词开始搜索');
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(_error!),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_tracks.isEmpty && _albums.isEmpty && _artists.isEmpty) {
      return _buildEmpty('未找到相关结果');
    }

    return ListView(
      children: <Widget>[
        if (_tracks.isNotEmpty) ...<Widget>[
          _sectionHeader('歌曲'),
          ..._tracks.map((SongEntity song) => MediaListTile(
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
                onTap: () {
                  final List<SongEntity> songs = _tracks;
                  if (songs.isEmpty) return;
                  FnPlayerService.instance
                      .setQueue(songs, index: _tracks.indexOf(song))
                      .then((_) => FnPlayerService.instance.play())
                      .then((_) {
                        if (!context.mounted) return;
                        openPlayerPage(context);
                      });
                },
              )),
        ],
        if (_albums.isNotEmpty) ...<Widget>[
          _sectionHeader('专辑'),
          ..._albums.map((FnAlbum album) => MediaListTile(
                imageUrl: ApiClient.instance.coverUrl(album.coverId),
                title: album.name,
                subtitle: album.year?.toString(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<dynamic>(
                    builder: (_) => AlbumDetailPage(albumGuid: album.guid),
                  ),
                ),
              )),
        ],
        if (_artists.isNotEmpty) ...<Widget>[
          _sectionHeader('歌手'),
          ..._artists.map((FnArtist artist) => MediaListTile(
                imageUrl: ApiClient.instance.coverUrl(artist.coverId),
                title: artist.name,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<dynamic>(
                    builder: (_) => ArtistDetailPage(artistGuid: artist.guid, artistName: artist.name),
                  ),
                ),
              )),
        ],
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  Widget _buildEmpty(String message) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.search_off, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
