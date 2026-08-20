import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/state/song_state.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/list/media_list_tile.dart';

/// 流派浏览（列表）。
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
      appBar: AppBar(title: const Text('流派')),
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
              : ListView.builder(
                  itemCount: _genres.length,
                  itemBuilder: (context, index) {
                    final FnGenre genre = _genres[index];
                    return MediaListTile(
                      leadingWidget: const Icon(Icons.category_outlined),
                      title: genre.name,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<dynamic>(
                          builder: (_) => GenreDetailPage(genreGuid: genre.guid, genreName: genre.name),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

/// 流派详情：曲目列表。
class GenreDetailPage extends StatefulWidget {
  const GenreDetailPage({super.key, required this.genreGuid, required this.genreName});

  final String genreGuid;
  final String genreName;

  @override
  State<GenreDetailPage> createState() => _GenreDetailPageState();
}

class _GenreDetailPageState extends State<GenreDetailPage> {
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
          await FnGenreService.instance.fetchGenreTracks(widget.genreGuid);
      if (!mounted) return;
      setState(() {
        _tracks = tracks.map(SongEntity.fromTrack).toList()
          ..sort((SongEntity a, SongEntity b) => NaturalSort.compare(a.title, b.title));
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.genreName)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _tracks.length,
                  itemBuilder: (context, index) {
                    final SongEntity song = _tracks[index];
                    return MediaListTile(
                      title: song.title,
                      subtitle: song.artistDisplay,
                      trailing: Text(
                        song.durationDisplay,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                      ),
                      onTap: () {},
                    );
                  },
                ),
    );
  }
}
