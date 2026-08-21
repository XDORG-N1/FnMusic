import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router/app_router.dart';
import '../../app/services/feiniu/feiniu_services.dart';
import '../../components/common/alphabet_indexer.dart';
import '../../components/common/artwork_widget.dart';
import '../../components/list/sort_sheet.dart';
import 'library_detail_pages.dart';

/// 专辑浏览（网格 + 服务端排序 + 分页 + 字母索引）。
class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  static const String route = '/library/albums';

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  static const String _prefsSortMode = 'albums_sort_mode_v1';
  static const String _prefsSortAscending = 'albums_sort_ascending_v1';
  static const String _prefsGridColumns = 'albums_grid_columns_v1';

  /// 默认按最近添加降序（`newTrackAddedAt` 已在真实 FNOS 验证可用）。
  static const String _defaultSortMode = 'newTrackAddedAt';
  static const bool _defaultAscending = false;

  final List<FnAlbum> _albums = <FnAlbum>[];
  final ScrollController _scrollController = ScrollController();

  String _sortMode = _defaultSortMode;
  bool _ascending = _defaultAscending;
  int _gridColumns = 2;

  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  bool _previewVisible = false;
  String? _previewLetter;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_loadPrefsThenLoad());
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- 数据加载 ----------

  Future<void> _loadPrefsThenLoad() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String mode =
        (prefs.getString(_prefsSortMode) ?? _defaultSortMode).trim();
    final bool asc = prefs.getBool(_prefsSortAscending) ?? _defaultAscending;
    int cols = prefs.getInt(_prefsGridColumns) ?? 2;
    if (cols < 2) cols = 2;
    if (cols > 4) cols = 4;
    if (!mounted) return;
    setState(() {
      _sortMode = mode.isEmpty ? _defaultSortMode : mode;
      _ascending = asc;
      _gridColumns = cols;
    });
    await _loadFirstPage();
  }

  Future<void> _savePrefs() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSortMode, _sortMode);
    await prefs.setBool(_prefsSortAscending, _ascending);
    await prefs.setInt(_prefsGridColumns, _gridColumns);
  }

  String _apiSortParam() => '$_sortMode,${_ascending ? 'asc' : 'desc'}';

  Future<void> _loadFirstPage() async {
    setState(() {
      _page = 1;
      _hasMore = true;
      _loading = true;
      _error = null;
    });
    try {
      final ApiPage<FnAlbum> page =
          await FnAlbumService.instance.fetchAlbums(page: 1, sort: _apiSortParam());
      if (!mounted) return;
      setState(() {
        _albums
          ..clear()
          ..addAll(page.list);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    final int next = _page + 1;
    try {
      final ApiPage<FnAlbum> page =
          await FnAlbumService.instance.fetchAlbums(page: next, sort: _apiSortParam());
      if (!mounted) return;
      setState(() {
        _albums.addAll(page.list);
        _hasMore = page.hasMore;
        _page = next;
      });
    } catch (_) {
      // 加载更多失败静默：下次滚动再试。
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 600) {
      unawaited(_loadMore());
    }
  }

  // ---------- 排序面板 ----------

  void _showSortSheet() {
    showSortSheet(
      context,
      SortSheet(
        title: '专辑排序',
        options: const <SortOption>[
          SortOption(key: 'newTrackAddedAt', label: '更新日期', icon: Icons.update),
          SortOption(key: 'releaseYear', label: '发行年份', icon: Icons.calendar_today),
          SortOption(key: 'name', label: '专辑名', icon: Icons.sort_by_alpha),
          SortOption(key: 'artistName', label: '歌手名', icon: Icons.person),
          SortOption(key: 'trackCount', label: '歌曲数', icon: Icons.music_note_outlined),
        ],
        currentKey: _sortMode,
        ascending: _ascending,
        onSelectKey: (String value) {
          _sortMode = value;
          unawaited(_savePrefs());
          unawaited(_loadFirstPage());
        },
        onSelectAscending: (bool value) {
          _ascending = value;
          unawaited(_savePrefs());
          unawaited(_loadFirstPage());
        },
        extra: Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
          child: SegmentedButton<int>(
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 2, label: Text('二列'), icon: Icon(Icons.grid_view_rounded)),
              ButtonSegment<int>(value: 3, label: Text('三列'), icon: Icon(Icons.grid_view_rounded)),
              ButtonSegment<int>(value: 4, label: Text('四列'), icon: Icon(Icons.grid_view_rounded)),
            ],
            selected: <int>{_gridColumns},
            onSelectionChanged: (Set<int> selection) {
              setState(() => _gridColumns = selection.first);
              unawaited(_savePrefs());
            },
            showSelectedIcon: false,
          ),
        ),
      ),
    );
  }

  // ---------- 字母索引 ----------

  void _activateIndexPreview(String letter) {
    _previewTimer?.cancel();
    setState(() {
      _previewLetter = letter;
      _previewVisible = true;
    });
  }

  void _scheduleHideIndexPreview() {
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _previewVisible = false);
    });
  }

  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    final int cols = _gridColumns;
    final double itemWidth = (MediaQuery.sizeOf(context).width - 32 - 16 * (cols - 1)) / cols;
    final double itemHeight = itemWidth / _aspectRatioForColumns(cols);
    final int row = index ~/ cols;
    final double offset = (row * (itemHeight + 16)).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(offset);
  }

  static double _aspectRatioForColumns(int cols) {
    return switch (cols) {
      3 => 0.65,
      4 => 0.57,
      _ => 0.76,
    };
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('专辑'),
        actions: <Widget>[
          SortActionButton(onTap: _showSortSheet),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.search),
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
                      OutlinedButton(onPressed: _loadFirstPage, child: const Text('重试')),
                    ],
                  ),
                )
              : _albums.isEmpty
                  ? const Center(child: Text('暂无专辑'))
                  : _buildGrid(),
    );
  }

  Widget _buildGrid() {
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: Stack(
        children: <Widget>[
          GridView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: _aspectRatioForColumns(_gridColumns),
            ),
            itemCount: _albums.length + (_loadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _albums.length) {
                return const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              return _AlbumCell(
                album: _albums[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<dynamic>(
                    builder: (_) => AlbumDetailPage(
                      albumGuid: _albums[index].guid,
                      albumName: _albums[index].name,
                      albumCoverId: _albums[index].coverId,
                      albumYear: _albums[index].year,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            right: 2,
            top: 4,
            bottom: 4,
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
              controller: _scrollController,
              itemCount: _albums.length,
              itemExtent: 0,
              getLabel: (int index) =>
                  IndexUtils.leadingLetter(_albums[index].name),
              onScrollRequest: _scrollToIndex,
              onIndexChanged: _activateIndexPreview,
              onDragEnd: _scheduleHideIndexPreview,
            ),
          ),
        ],
      ),
    );
  }
}

/// 专辑网格单元格：封面 + 名称 + 首数/年份。
class _AlbumCell extends StatelessWidget {
  final FnAlbum album;
  final VoidCallback onTap;

  const _AlbumCell({required this.album, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String subtitle = album.trackCount != null
        ? '${album.trackCount}首'
        : (album.year?.toString() ?? '');
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ArtworkWidget(
              imageUrl: ApiClient.instance.coverUrl(album.coverId),
              size: double.infinity,
              borderRadius: BorderRadius.circular(14),
              placeholderText: album.name,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          if (subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
