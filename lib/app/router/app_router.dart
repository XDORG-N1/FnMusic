import 'package:flutter/material.dart';
import '../../components/player/mini_player/mini_player_bar.dart';
import '../../pages/home/favorite_page.dart';
import '../../pages/home/home_page.dart';
import '../../pages/home/recent_page.dart';
import '../../pages/library/albums_page.dart';
import '../../pages/library/artists_page.dart';
import '../../pages/library/folders_page.dart';
import '../../pages/library/genres_page.dart';
import '../../pages/library/library_page.dart';
import '../../pages/library/playlists_page.dart';
import '../../pages/player/player_page.dart';
import '../../pages/profile/listening_report_page.dart';
import '../../pages/profile/listening_stats_page.dart';
import '../../pages/profile/profile_page.dart';
import '../../pages/search/search_page.dart';
import '../../pages/settings/about_page.dart';
import '../../pages/settings/backup_restore_page.dart';
import '../../pages/settings/cache_settings_page.dart';
import '../../pages/settings/lyrics_settings_page.dart';
import '../../pages/settings/permission_settings_page.dart';
import '../../pages/settings/settings_page.dart';
import '../state/layout_settings.dart';
import '../state/player_state.dart';
import '../state/song_state.dart';
import '../../pages/songs/songs_page.dart';

/// 应用路由常量表。
abstract class AppRoutes {
  static const String home = '/home';
  static const String library = '/library';
  static const String search = '/search';
  static const String profile = '/profile';
  static const String settings = '/settings';
  static const String player = '/player';

  /// 启动时初始路由（实际由启动门决定展示内容）。
  static const String initial = home;
}

/// 主路由表。压栈页面在此登记；启动门 / 登录等由 app.dart 处理。
class AppRouter {
  AppRouter._();

  static Map<String, WidgetBuilder> get routes => <String, WidgetBuilder>{
        AppRoutes.home: (_) => const HomePage(),
        AppRoutes.library: (_) => const LibraryPage(),
        AppRoutes.search: (_) => const SearchPage(),
        AppRoutes.profile: (_) => const ProfilePage(),
        AppRoutes.settings: (_) => const SettingsPage(),
        AppRoutes.player: (_) => const PlayerPage(),
        SongsPage.route: (_) => const SongsPage(),
        AlbumsPage.route: (_) => const AlbumsPage(),
        ArtistsPage.route: (_) => const ArtistsPage(),
        GenresPage.route: (_) => const GenresPage(),
        PlaylistsPage.route: (_) => const PlaylistsPage(),
        FoldersPage.route: (_) => const FoldersPage(),
        FavoritePage.route: (_) => const FavoritePage(),
        RecentPage.route: (_) => const RecentPage(),
        ListeningStatsPage.route: (_) => const ListeningStatsPage(),
        ListeningReportPage.route: (_) => const ListeningReportPage(),
        CacheSettingsPage.route: (_) => const CacheSettingsPage(),
        PermissionSettingsPage.route: (_) => const PermissionSettingsPage(),
        LyricsSettingsPage.route: (_) => const LyricsSettingsPage(),
        BackupRestorePage.route: (_) => const BackupRestorePage(),
        AboutPage.route: (_) => const AboutPage(),
      };
}

/// 主导航壳：底部 4 个 tab（首页 / 音乐库 / 搜索 / 我的）。
/// 使用 IndexedStack 保持各 tab 状态。
class PrimaryNavigationShell extends StatefulWidget {
  const PrimaryNavigationShell({super.key});

  @override
  State<PrimaryNavigationShell> createState() => _PrimaryNavigationShellState();
}

class _PrimaryNavigationShellState extends State<PrimaryNavigationShell> {
  int _index = 0;

  /// 宽屏断点：达到此宽度切换为侧边栏导航（平板布局）。
  static const double _sideNavBreakpoint = 720;

  static const List<Widget> _pages = <Widget>[
    HomePage(),
    LibraryPage(),
    SearchPage(),
    ProfilePage(),
  ];

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: '首页',
    ),
    NavigationDestination(
      icon: Icon(Icons.library_music_outlined),
      selectedIcon: Icon(Icons.library_music),
      label: '音乐库',
    ),
    NavigationDestination(
      icon: Icon(Icons.search_outlined),
      selectedIcon: Icon(Icons.search),
      label: '搜索',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= _sideNavBreakpoint) {
          return _buildWideLayout();
        }
        return _buildNarrowLayout();
      },
    );
  }

  /// 窄屏（手机）：底部导航栏 + 迷你播放器。
  Widget _buildNarrowLayout() {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const _MiniPlayerSlot(),
          NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (int value) {
              setState(() => _index = value);
            },
            destinations: _destinations,
          ),
        ],
      ),
    );
  }

  /// 宽屏（平板）：侧边导航栏 + 内容区（迷你播放器置底）。
  Widget _buildWideLayout() {
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (int value) {
              setState(() => _index = value);
            },
            labelType: NavigationRailLabelType.all,
            destinations: _destinations
                .map((NavigationDestination d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Expanded(child: IndexedStack(index: _index, children: _pages)),
                const _MiniPlayerSlot(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 迷你播放器插槽：全屏播放器激活或无播放内容时隐藏。
class _MiniPlayerSlot extends StatelessWidget {
  const _MiniPlayerSlot();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLayoutSettings.playerRouteActive,
      builder: (context, playerRouteActive, _) {
        if (playerRouteActive) return const SizedBox.shrink();
        return ValueListenableBuilder<SongEntity?>(
          valueListenable: AppPlayerState.instance.currentSong,
          builder: (context, song, _) {
            if (song == null) return const SizedBox.shrink();
            return const MiniPlayerBar();
          },
        );
      },
    );
  }
}
