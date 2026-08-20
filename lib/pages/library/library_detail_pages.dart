import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/state/song_state.dart';
import '../../components/list/media_list_tile.dart';

/// 专辑详情：曲目列表。
class AlbumDetailPage extends StatefulWidget {
  const AlbumDetailPage({super.key, required this.albumGuid});

  final String albumGuid;

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
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
          await FnAlbumService.instance.fetchAlbumTracks(widget.albumGuid);
      if (!mounted) return;
      setState(() {
        // CUE 整轨：按镜像累计起始偏移（专辑上下文零额外网络）。
        _tracks = FnCueService.instance.withCueOffsets(
          tracks.map(SongEntity.fromTrack).toList(),
          tracks,
        );
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
      appBar: AppBar(title: const Text('专辑')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final SongEntity song = _tracks[index];
                    return MediaListTile(
                      imageUrl:
                          ApiClient.instance.coverUrl(song.coverId),
                      title: '${index + 1}  ${song.title}',
                      subtitle: song.artistDisplay,
                      trailing: Text(song.durationDisplay),
                      onTap: () {},
                    );
                  },
                ),
    );
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
                      onTap: () {},
                    );
                  },
                ),
    );
  }
}
