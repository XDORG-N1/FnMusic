import 'package:flutter/material.dart';

import 'albums_page.dart';
import 'artists_page.dart';
import 'folders_page.dart';
import 'genres_page.dart';
import 'playlists_page.dart';
import '../home/favorite_page.dart';
import '../songs/songs_page.dart';

/// 音乐库：各类别入口网格。
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  static const List<_LibraryEntry> _entries = <_LibraryEntry>[
    _LibraryEntry(Icons.favorite_outline, '收藏', Colors.pink, FavoritePage.route),
    _LibraryEntry(Icons.music_note_outlined, '全部歌曲', Colors.red, SongsPage.route),
    _LibraryEntry(Icons.album_outlined, '专辑', Colors.blue, AlbumsPage.route),
    _LibraryEntry(Icons.people_outline, '歌手', Colors.green, ArtistsPage.route),
    _LibraryEntry(Icons.category_outlined, '流派', Colors.purple, GenresPage.route),
    _LibraryEntry(Icons.queue_music, '歌单', Colors.orange, PlaylistsPage.route),
    _LibraryEntry(Icons.folder_outlined, '文件夹', Colors.teal, FoldersPage.route),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('音乐库')),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: _entries.map((_LibraryEntry e) {
          return _LibraryEntryCard(entry: e);
        }).toList(),
      ),
    );
  }
}

class _LibraryEntry {
  const _LibraryEntry(this.icon, this.label, this.color, this.route);
  final IconData icon;
  final String label;
  final Color color;
  final String route;
}

class _LibraryEntryCard extends StatelessWidget {
  const _LibraryEntryCard({required this.entry});

  final _LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => Navigator.of(context).pushNamed(entry.route),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(entry.icon, size: 28, color: entry.color),
          ),
          const SizedBox(height: 8),
          Text(
            entry.label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
