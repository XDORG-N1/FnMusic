import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/services/player_service.dart';
import '../../app/state/song_state.dart';
import '../../pages/library/library_detail_pages.dart';
import 'add_to_playlist_sheet.dart';

/// 曲目「更多」菜单：加入歌单 / 下一首播放 / 加入播放队列 / 收藏 /
/// 查看专辑 / 查看歌手；歌单详情场景额外提供「从歌单移除」。
class TrackActionsMenu extends StatelessWidget {
  const TrackActionsMenu({
    super.key,
    required this.track,
    this.showRemoveFromPlaylist = false,
    this.onRemoveFromPlaylist,
  });

  final SongEntity track;
  final bool showRemoveFromPlaylist;
  final VoidCallback? onRemoveFromPlaylist;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      icon: const Icon(Icons.more_vert),
      onSelected: (String value) => _handle(context, value),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        _menuItem('addToPlaylist', Icons.playlist_add, '加入歌单'),
        _menuItem('playNext', Icons.skip_next, '下一首播放'),
        _menuItem('addToQueue', Icons.queue_music, '加入播放队列'),
        _menuItem(
          'favorite',
          track.isFavorite ? Icons.favorite : Icons.favorite_outline,
          track.isFavorite ? '取消收藏' : '收藏',
        ),
        if (track.albumGuid != null && track.albumGuid!.isNotEmpty)
          _menuItem('viewAlbum', Icons.album_outlined, '查看专辑'),
        if (track.artistGuids.isNotEmpty)
          _menuItem('viewArtist', Icons.person_outline, '查看歌手'),
        if (showRemoveFromPlaylist)
          _menuItem(
            'removeFromPlaylist',
            Icons.remove_circle_outline,
            '从歌单移除',
          ),
      ],
    );
  }

  void _handle(BuildContext context, String value) {
    switch (value) {
      case 'addToPlaylist':
        unawaited(showAddToPlaylistSheet(context, track));
      case 'playNext':
        FnPlayerService.instance.insertNext(<SongEntity>[track]);
        _toast(context, '已加入下一首播放');
      case 'addToQueue':
        FnPlayerService.instance.addToQueue(<SongEntity>[track]);
        _toast(context, '已加入播放队列');
      case 'favorite':
        unawaited(_toggleFavorite(context));
      case 'viewAlbum':
        Navigator.of(context).push(
          MaterialPageRoute<dynamic>(
            builder: (_) => AlbumDetailPage(
              albumGuid: track.albumGuid!,
              albumName: track.albumDisplay,
            ),
          ),
        );
      case 'viewArtist':
        Navigator.of(context).push(
          MaterialPageRoute<dynamic>(
            builder: (_) => ArtistDetailPage(
              artistGuid: track.artistGuids.first,
              artistName: track.artistDisplay,
            ),
          ),
        );
      case 'removeFromPlaylist':
        onRemoveFromPlaylist?.call();
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleFavorite(BuildContext context) async {
    final bool target = !track.isFavorite;
    try {
      if (target) {
        await FeiNiuFavoriteService.instance.favorite(track.guid);
      } else {
        await FeiNiuFavoriteService.instance.unfavorite(track.guid);
      }
      if (!context.mounted) return;
      _toast(context, target ? '已收藏' : '已取消收藏');
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, '操作失败：$e');
    }
  }
}

PopupMenuItem<String> _menuItem(
  String value,
  IconData icon,
  String label,
) {
  return PopupMenuItem<String>(
    value: value,
    child: ListTile(
      leading: Icon(icon),
      title: Text(label),
    ),
  );
}
