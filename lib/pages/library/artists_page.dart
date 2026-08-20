import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/utils/natural_sort.dart';
import '../../components/common/alphabet_indexer.dart';
import '../../components/list/media_list_tile.dart';
import 'library_detail_pages.dart';

/// 歌手浏览（拼音排序列表 + 右侧字母索引）。
class ArtistsPage extends StatefulWidget {
  const ArtistsPage({super.key});

  static const String route = '/library/artists';

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  /// 列表项固定高度（ListTile 无副标题默认 56），用于字母索引精确跳转。
  static const double _itemExtent = 56.0;

  final ScrollController _controller = ScrollController();
  List<FnArtist> _artists = <FnArtist>[];
  bool _loading = true;
  String? _error;

  bool _previewVisible = false;
  String? _previewLetter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ApiPage<FnArtist> page = await FnArtistService.instance.fetchArtists();
      final List<FnArtist> list = List<FnArtist>.from(page.list)
        ..sort((FnArtist a, FnArtist b) => NaturalSort.compare(a.name, b.name));
      if (!mounted) return;
      setState(() {
        _artists = list;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _activateIndexPreview(String letter) {
    setState(() {
      _previewLetter = letter;
      _previewVisible = true;
    });
  }

  void _scheduleHideIndexPreview() {
    setState(() => _previewVisible = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歌手')),
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
              : _buildList(),
    );
  }

  Widget _buildList() {
    return Stack(
      children: <Widget>[
        ListView.builder(
          controller: _controller,
          itemExtent: _itemExtent,
          padding: const EdgeInsets.only(right: 4),
          itemCount: _artists.length,
          itemBuilder: (context, index) {
            final FnArtist artist = _artists[index];
            return MediaListTile(
              imageUrl: ApiClient.instance.coverUrl(artist.coverId),
              title: artist.name,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<dynamic>(
                  builder: (_) => ArtistDetailPage(
                    artistGuid: artist.guid,
                    artistName: artist.name,
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          right: 36,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _previewVisible && _previewLetter != null ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Align(
                alignment: Alignment.centerRight,
                child: _previewLetter == null
                    ? const SizedBox.shrink()
                    : IndexPreview(
                        text: _previewLetter!,
                        visible: _previewVisible,
                      ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 2,
          top: 4,
          bottom: 4,
          child: DraggableScrollbar(
            controller: _controller,
            itemCount: _artists.length,
            itemExtent: _itemExtent,
            getLabel: (int index) =>
                IndexUtils.leadingLetter(_artists[index].name),
            onIndexChanged: _activateIndexPreview,
            onDragEnd: _scheduleHideIndexPreview,
          ),
        ),
      ],
    );
  }
}
