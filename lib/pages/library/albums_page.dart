import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/common/artwork_widget.dart';
import 'library_detail_pages.dart';

/// 专辑浏览（网格）。
class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  static const String route = '/library/albums';

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  List<FnAlbum> _albums = <FnAlbum>[];
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
      final ApiPage<FnAlbum> page = await FnAlbumService.instance.fetchAlbums();
      final List<FnAlbum> list = List<FnAlbum>.from(page.list)
        ..sort((FnAlbum a, FnAlbum b) => NaturalSort.compare(a.name, b.name));
      if (!mounted) return;
      setState(() {
        _albums = list;
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
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: _albums.length,
                  itemBuilder: (context, index) {
                    final FnAlbum album = _albums[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<dynamic>(
                          builder: (_) => AlbumDetailPage(albumGuid: album.guid),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: ArtworkWidget(
                              imageUrl: ApiClient.instance.coverUrl(album.coverId),
                              size: double.infinity,
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            album.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            '${album.year ?? ''}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
