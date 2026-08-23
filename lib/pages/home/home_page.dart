import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router/app_router.dart';
import '../../app/services/feiniu/api_client.dart';
import '../../app/services/feiniu/api_models.dart';
import '../../app/services/feiniu/album_service.dart';
import '../../app/services/feiniu/auth_service.dart';
import '../../app/services/feiniu/favorite_service.dart';
import '../../app/services/feiniu/playlist_service.dart';
import '../../app/services/feiniu/track_service.dart';
import '../../app/services/player_service.dart';
import '../../app/services/session_cache.dart';
import '../../app/state/song_state.dart';
import '../../components/common/artwork_widget.dart';
import '../library/albums_page.dart';
import '../library/artists_page.dart';
import '../library/genres_page.dart';
import '../library/library_detail_pages.dart';
import '../library/playlists_page.dart';
import '../songs/songs_page.dart';
import 'favorite_page.dart';
import 'recent_page.dart';

/// 首页仪表盘缓存（SharedPreferences JSON，离线也能快速渲染）。
class _HomeCacheData {
  _HomeCacheData({
    this.favorites,
    this.recentSongs,
    this.recentAlbums,
    this.playlists,
    this.recentTracks,
  });

  final List<SongEntity>? favorites;
  final List<SongEntity>? recentSongs;
  final List<FnAlbum>? recentAlbums;
  final List<FnPlaylist>? playlists;
  final List<SongEntity>? recentTracks;

  static const String prefKey = SessionCache.homeDashboardKey;

  Map<String, Object?> toJson() => <String, Object?>{
        'favorites': favorites?.map((SongEntity s) => s.toJson()).toList(),
        'recentSongs': recentSongs?.map((SongEntity s) => s.toJson()).toList(),
        'recentAlbums': recentAlbums
            ?.map((FnAlbum a) => <String, Object?>{
                  'guid': a.guid,
                  'name': a.name,
                  'coverId': a.coverId,
                  'year': a.year,
                  'trackCount': a.trackCount,
                })
            .toList(),
        'playlists': playlists
            ?.map((FnPlaylist p) => <String, Object?>{
                  'guid': p.guid,
                  'name': p.name,
                  'coverId': p.coverId,
                  'createdAt': p.createdAt,
                  'trackCount': p.trackCount,
                })
            .toList(),
        'recentTracks': recentTracks?.map((SongEntity s) => s.toJson()).toList(),
      };

  factory _HomeCacheData.fromJson(Map<String, Object?> json) {
    List<SongEntity>? songs(Object? key) =>
        (json[key] as List<Object?>?)
            ?.whereType<Map<Object?, Object?>>()
            .map((Map<Object?, Object?> m) =>
                SongEntity.fromJson(m.cast<String, Object?>()))
            .toList();
    List<FnAlbum>? albums() => (json['recentAlbums'] as List<Object?>?)
        ?.whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnAlbum.fromJson(m.cast<String, Object?>()))
        .toList();
    List<FnPlaylist>? playlists() => (json['playlists'] as List<Object?>?)
        ?.whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> m) =>
            FnPlaylist.fromJson(m.cast<String, Object?>()))
        .toList();
    return _HomeCacheData(
      favorites: songs('favorites'),
      recentSongs: songs('recentSongs'),
      recentAlbums: albums(),
      playlists: playlists(),
      recentTracks: songs('recentTracks'),
    );
  }
}

/// 首页 — 云端音乐仪表板。
///
/// 区块：漫游 Hero Banner → 快捷菜单 → 最近播放/收藏入口 → 我的歌单 →
/// 最新歌曲 → 最新专辑。数据全部来自真实 FNOS API，并持久缓存首屏。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FnPlayerService _player = FnPlayerService.instance;

  bool _loading = true;

  // 漫游 Hero
  SongEntity? _roamSong;
  String _roamId = '';

  // 各区块数据
  List<SongEntity> _favorites = <SongEntity>[];
  List<SongEntity> _recentSongs = <SongEntity>[];
  List<FnAlbum> _recentAlbums = <FnAlbum>[];
  List<FnPlaylist> _playlists = <FnPlaylist>[];
  List<SongEntity> _recentTracks = <SongEntity>[];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void didUpdateWidget(HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 登录切换账号后（shell 重建但 IndexedStack 保留本页）重新拉取。
  }

  // ---------- 数据加载 ----------

  Future<void> _loadAll({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      await _restoreCache();
    }
    if (!mounted || !_sessionActive) return;
    await Future.wait(<Future<void>>[
      _loadRoam(),
      _loadFavorites(),
      _loadRecentHistory(),
      _loadRecentAlbums(),
      _loadPlaylists(),
      _loadRecentTracks(),
    ]);
    if (!mounted || !_sessionActive) return;
    setState(() {
      _loading = false;
    });
    await _writeCache();
  }

  /// 会话是否仍有效（登出 / 401 回退后不再更新页面、不再写缓存）。
  bool get _sessionActive =>
      AuthService.instance.status.value == AuthStatus.loggedIn;

  /// 从本地缓存渲染首屏（失败静默忽略）。
  Future<void> _restoreCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_HomeCacheData.prefKey);
      if (raw == null || raw.isEmpty) return;
      final _HomeCacheData cached = _HomeCacheData.fromJson(
        (jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>(),
      );
      if (!mounted) return;
      setState(() {
        _favorites = cached.favorites ?? _favorites;
        _recentSongs = cached.recentSongs ?? _recentSongs;
        _recentAlbums = cached.recentAlbums ?? _recentAlbums;
        _playlists = cached.playlists ?? _playlists;
        _recentTracks = cached.recentTracks ?? _recentTracks;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[HomePage] cache restore error: $e');
    }
  }

  Future<void> _writeCache() async {
    // 会话已失效（401 登出）时不写脏数据，避免登出清理后又被写回。
    if (!_sessionActive) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final _HomeCacheData data = _HomeCacheData(
        favorites: _favorites,
        recentSongs: _recentSongs,
        recentAlbums: _recentAlbums,
        playlists: _playlists,
        recentTracks: _recentTracks,
      );
      await prefs.setString(
        _HomeCacheData.prefKey,
        jsonEncode(data.toJson()),
      );
    } catch (e) {
      debugPrint('[HomePage] cache write error: $e');
    }
  }

  Future<void> _loadRoam() async {
    try {
      final String deviceId = AuthService.instance.getOrCreateDeviceId();
      final FnRoamStartResponse response =
          await ApiClient.instance.roamStart(deviceId);
      if (!mounted) return;
      setState(() {
        _roamId = response.current.roamId;
        _roamSong = SongEntity.fromTrack(response.current.track);
      });
    } catch (e) {
      debugPrint('[HomePage] roam error: $e');
    }
  }

  /// 换一首漫游歌（不打断播放）：沿当前漫游链取下一首。
  Future<void> _refreshRoam() async {
    final String currentRoamId = _roamId;
    if (currentRoamId.isEmpty) {
      await _loadRoam();
      return;
    }
    try {
      final String deviceId = AuthService.instance.getOrCreateDeviceId();
      final FnRoamNextResponse response =
          await ApiClient.instance.roamNext(deviceId, currentRoamId);
      final FnRoamTrack? next = response.next;
      if (next == null || !mounted) return;
      setState(() {
        _roamId = next.roamId;
        _roamSong = SongEntity.fromTrack(next.track);
      });
    } catch (e) {
      debugPrint('[HomePage] refresh roam error: $e');
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final List<FnTrack> tracks =
          await FeiNiuFavoriteService.instance.fetchFavoriteTracks();
      if (!mounted) return;
      setState(() {
        _favorites =
            tracks.take(10).map(SongEntity.fromTrack).toList();
      });
    } catch (e) {
      debugPrint('[HomePage] favorites error: $e');
    }
  }

  Future<void> _loadRecentHistory() async {
    try {
      final List<FnTrack> tracks =
          await ApiClient.instance.getPlayHistory(page: 1, size: 10);
      if (!mounted) return;
      setState(() {
        _recentSongs = tracks.map(SongEntity.fromTrack).toList();
      });
    } catch (e) {
      debugPrint('[HomePage] history error: $e');
    }
  }

  Future<void> _loadRecentAlbums() async {
    try {
      final ApiPage<FnAlbum> page = await FnAlbumService.instance
          .fetchAlbums(sort: 'newTrackAddedAt,desc');
      if (!mounted) return;
      setState(() {
        _recentAlbums = page.list.take(10).toList();
      });
    } catch (e) {
      debugPrint('[HomePage] albums error: $e');
    }
  }

  Future<void> _loadPlaylists() async {
    try {
      final List<FnPlaylist> list =
          await FnPlaylistService.instance.fetchPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = list.take(10).toList();
      });
    } catch (e) {
      debugPrint('[HomePage] playlists error: $e');
    }
  }

  Future<void> _loadRecentTracks() async {
    try {
      final ApiPage<FnTrack> page =
          await FnTrackService.instance.fetchTracks(sort: 'createdAt,desc');
      if (!mounted) return;
      setState(() {
        _recentTracks = page.list
            .take(10)
            .map(SongEntity.fromTrack)
            .toList();
      });
    } catch (e) {
      debugPrint('[HomePage] recent tracks error: $e');
    }
  }

  // ---------- 播放 ----------

  /// 播放 Hero 漫游歌：进入漫游模式，播完/下一曲沿同一条链续播。
  Future<void> _playRoam() async {
    final SongEntity? song = _roamSong;
    if (song == null) return;
    final String deviceId = AuthService.instance.getOrCreateDeviceId();
    if (_roamId.isEmpty) {
      await _player.setQueue(<SongEntity>[song]);
      await _player.play();
      return;
    }
    await _player.playRoamSong(song, deviceId, _roamId);
  }

  Future<void> _playList(List<SongEntity> songs, {int index = 0}) async {
    if (songs.isEmpty) return;
    await _player.setQueue(songs, index: index.clamp(0, songs.length - 1));
    await _player.play();
  }

  Future<void> _playRecent() => _playList(_recentSongs);
  Future<void> _playFavorites() => _playList(_favorites);

  Future<void> _playHomeSong(SongEntity song, List<SongEntity> songs) async {
    final int index = songs.indexWhere((SongEntity s) => s.guid == song.guid);
    await _playList(songs, index: index < 0 ? 0 : index);
  }

  // ---------- 导航 ----------

  void _openSearch() => Navigator.pushNamed(context, AppRoutes.search);

  void _openRecent() => Navigator.pushNamed(context, RecentPage.route);

  void _openFavorite() => Navigator.pushNamed(context, FavoritePage.route);

  void _openSongs() => Navigator.pushNamed(context, SongsPage.route);

  void _openAlbums() => Navigator.pushNamed(context, AlbumsPage.route);

  void _openArtists() => Navigator.pushNamed(context, ArtistsPage.route);

  void _openGenres() => Navigator.pushNamed(context, GenresPage.route);

  void _openPlaylists() => Navigator.pushNamed(context, PlaylistsPage.route);

  void _openAlbumDetail(FnAlbum album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailPage(albumGuid: album.guid),
      ),
    );
  }

  void _openPlaylistDetail(FnPlaylist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailPage(
          playlistGuid: playlist.guid,
          playlistName: playlist.name,
        ),
      ),
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: _openSearch,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      // 静态占位：避免离线/测试环境无限转圈（缓存首屏渲染后立即替换）。
      return const _HomeLoadingPlaceholder();
    }
    return RefreshIndicator(
      onRefresh: () => _loadAll(forceRefresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
        children: <Widget>[
          // 1. 漫游 Hero Banner
          if (_roamSong != null) ...[
            _HeroBanner(
              song: _roamSong!,
              onPlay: _playRoam,
              onRefresh: _refreshRoam,
            ),
            const SizedBox(height: 20),
          ],

          // 2. 快捷菜单 — 歌曲 / 歌手 / 专辑 / 风格
          _ShortcutMenu(
            items: <_ShortcutItem>[
              _ShortcutItem(
                icon: Icons.music_note_rounded,
                label: '歌曲',
                color: const Color(0xFF3B82F6),
                onTap: _openSongs,
              ),
              _ShortcutItem(
                icon: Icons.people_rounded,
                label: '歌手',
                color: const Color(0xFF14B8A6),
                onTap: _openArtists,
              ),
              _ShortcutItem(
                icon: Icons.album_rounded,
                label: '专辑',
                color: const Color(0xFFA855F7),
                onTap: _openAlbums,
              ),
              _ShortcutItem(
                icon: Icons.music_video_rounded,
                label: '风格',
                color: const Color(0xFFF97316),
                onTap: _openGenres,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // 3. 功能入口 — 最近播放 / 收藏
          _QuickActions(
            actions: <_QuickAction>[
              _QuickAction(
                icon: Icons.history_rounded,
                title: '最近播放',
                subtitle: '接着上次听',
                color: const Color(0xFF14B8A6),
                onTap: _openRecent,
                onPlay: _playRecent,
              ),
              _QuickAction(
                icon: Icons.favorite_rounded,
                title: '收藏',
                subtitle: '我的最爱',
                color: const Color(0xFFEC4899),
                onTap: _openFavorite,
                onPlay: _playFavorites,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 4. 我的歌单 — 横向封面轮播
          if (_playlists.isNotEmpty) ...[
            _SectionHeader(title: '我的歌单', onViewAll: _openPlaylists),
            _CoverCarousel(
              coverSize: 100,
              borderRadius: 14,
              items: <_CoverItem>[
                for (final FnPlaylist p in _playlists)
                  _CoverItem(
                    imageUrl: p.coverId == null || p.coverId!.isEmpty
                        ? null
                        : ApiClient.instance.coverUrl(p.coverId!, size: 200),
                    icon: Icons.queue_music_rounded,
                    title: p.name,
                    subtitle: '',
                    onTap: () => _openPlaylistDetail(p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 5. 最新歌曲 — 紧凑竖排行列表
          if (_recentTracks.isNotEmpty) ...[
            _SectionHeader(title: '最新歌曲', onViewAll: _openSongs),
            _CompactSongList(
              songs: _recentTracks,
              onTap: (SongEntity song) => _playHomeSong(song, _recentTracks),
            ),
            const SizedBox(height: 16),
          ],

          // 6. 最新专辑 — 横向大封面轮播
          if (_recentAlbums.isNotEmpty) ...[
            _SectionHeader(title: '最新专辑', onViewAll: _openAlbums),
            _CoverCarousel(
              coverSize: 128,
              borderRadius: 16,
              items: <_CoverItem>[
                for (final FnAlbum a in _recentAlbums)
                  _CoverItem(
                    imageUrl: a.coverId == null || a.coverId!.isEmpty
                        ? null
                        : ApiClient.instance.coverUrl(a.coverId!, size: 300),
                    icon: Icons.album_rounded,
                    title: a.name,
                    subtitle: a.trackCount != null ? '${a.trackCount} 首' : '',
                    onTap: () => _openAlbumDetail(a),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // 空状态
          if (_favorites.isEmpty &&
              _recentSongs.isEmpty &&
              _recentAlbums.isEmpty &&
              _playlists.isEmpty &&
              _recentTracks.isEmpty)
            const _HomeEmptyState(text: '还没有数据，下拉刷新试试'),
        ],
      ),
    );
  }
}

// ---------- 区块组件 ----------

/// 区块标题：左侧标题 + 右侧「查看全部」。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onViewAll});

  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('查看全部'),
            ),
        ],
      ),
    );
  }
}

/// 横向封面轮播。
class _CoverCarousel extends StatelessWidget {
  const _CoverCarousel({
    required this.items,
    required this.coverSize,
    required this.borderRadius,
  });

  final List<_CoverItem> items;
  final double coverSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: coverSize + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int index) =>
            _buildItem(context, items[index]),
      ),
    );
  }

  Widget _buildItem(BuildContext context, _CoverItem item) {
    final double edge = coverSize;
    return SizedBox(
      width: edge,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: item.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ArtworkWidget(
              imageUrl: item.imageUrl,
              size: edge,
              borderRadius: BorderRadius.circular(borderRadius),
              placeholderIcon: item.icon,
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (item.subtitle.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoverItem {
  const _CoverItem({
    required this.title,
    required this.icon,
    this.imageUrl,
    this.subtitle = '',
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback? onTap;
}

/// 最新歌曲 — 紧凑竖排行列表。
class _CompactSongList extends StatelessWidget {
  const _CompactSongList({required this.songs, required this.onTap});

  final List<SongEntity> songs;
  final ValueChanged<SongEntity> onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<SongEntity> display = songs.take(5).toList();
    return Column(
      children: List<Widget>.generate(display.length, (int i) {
        final SongEntity song = display[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < display.length - 1 ? 6 : 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onTap(song),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  children: <Widget>[
                    ArtworkWidget(
                      imageUrl: ApiClient.instance.coverUrl(song.coverId, size: 120),
                      size: 44,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            song.artistDisplay ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.play_circle_outline_rounded,
                      size: 28,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// 漫游 Hero Banner：大封面为主角 + 歌名/歌手 + 播放/换一首。
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.song,
    required this.onPlay,
    required this.onRefresh,
  });

  final SongEntity song;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? coverUrl = song.coverId == null || song.coverId!.isEmpty
        ? null
        : ApiClient.instance.coverUrl(song.coverId!, size: 800);

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.35),
            scheme.tertiary.withValues(alpha: 0.18),
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          // 背景封面（放大模糊效果由透明度体现）
          Positioned.fill(
            child: Opacity(
              opacity: 0.35,
              child: ArtworkWidget(
                imageUrl: coverUrl,
                size: 800,
                borderRadius: BorderRadius.zero,
                placeholderIcon: Icons.graphic_eq_rounded,
              ),
            ),
          ),
          // 前景内容
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  ArtworkWidget(
                    imageUrl: coverUrl,
                    size: 120,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '今日漫游',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artistDisplay ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            IconButton.filled(
                              onPressed: onPlay,
                              icon: const Icon(Icons.play_arrow_rounded),
                              tooltip: '播放',
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: onRefresh,
                              icon: const Icon(Icons.refresh_rounded),
                              tooltip: '换一首',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 快捷菜单项。
class _ShortcutItem {
  const _ShortcutItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// 快捷菜单 — 歌曲 / 歌手 / 专辑 / 风格（2×2 或 4 联排）。
class _ShortcutMenu extends StatelessWidget {
  const _ShortcutMenu({required this.items});

  final List<_ShortcutItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _ShortcutTile(item: items[i])),
        ],
      ],
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({required this.item});

  final _ShortcutItem item;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: item.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: <Widget>[
              Icon(item.icon, size: 26, color: item.color),
              const SizedBox(height: 6),
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 功能入口项（最近播放 / 收藏）。
class _QuickAction {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    required this.onPlay,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPlay;
}

/// 功能入口行：标题 + 直接播放按钮。
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.actions});

  final List<_QuickAction> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _QuickActionTile(action: actions[i]),
        ],
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.action});

  final _QuickAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(action.icon, size: 22, color: action.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      action.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      action.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed: action.onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: '播放',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首屏加载占位（静态，无动画）。
class _HomeLoadingPlaceholder extends StatelessWidget {
  const _HomeLoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.music_note_rounded, size: 48, color: scheme.outline),
          const SizedBox(height: 12),
          Text(
            '加载中…',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}
