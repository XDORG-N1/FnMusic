import 'package:flutter/material.dart';

import '../../app/services/feiniu/feiniu_services.dart';
import '../../app/state/song_state.dart';
import '../common/artwork_widget.dart';

/// 弹出「加入歌单」面板：列出全部歌单 + 新建歌单入口。
///
/// 选择/新建歌单后加入当前歌曲并关闭面板；成功后由本函数在页面层
/// 弹 SnackBar 反馈（避免被面板遮挡）。面板内部错误（拉取失败等）就地显示。
Future<void> showAddToPlaylistSheet(BuildContext context, SongEntity track) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddToPlaylistSheet(track: track),
  ).then((String? playlistName) {
    if (playlistName == null || playlistName.isEmpty) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已加入《$playlistName》')));
  });
}

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({required this.track});

  final SongEntity track;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  List<FnPlaylist> _playlists = <FnPlaylist>[];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<FnPlaylist> playlists =
          await FnPlaylistService.instance.fetchPlaylists();
      if (!mounted) return;
      setState(() => _playlists = playlists);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTo(FnPlaylist playlist) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await FnPlaylistService.instance
          .addTrack(playlist.guid, widget.track.guid);
      if (!mounted) return;
      Navigator.of(context).pop(playlist.name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('加入失败：$e')));
    }
  }

  Future<void> _createAndAdd() async {
    if (_busy) return;
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '歌单名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final String guid = await FnPlaylistService.instance.createPlaylist(name);
      if (guid.isEmpty) throw StateError('创建歌单失败');
      await FnPlaylistService.instance.addTrack(guid, widget.track.guid);
      if (!mounted) return;
      Navigator.of(context).pop(name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Text(
                '加入歌单',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('新建歌单'),
              onTap: _busy ? null : _createAndAdd,
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        _error!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            else if (_playlists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    '暂无歌单，先新建一个吧',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final FnPlaylist playlist = _playlists[index];
                    return ListTile(
                      leading: ArtworkWidget(
                        imageUrl:
                            ApiClient.instance.coverUrl(playlist.coverId),
                        size: 44,
                        borderRadius: BorderRadius.circular(10),
                        placeholderIcon: Icons.queue_music,
                      ),
                      title: Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('${playlist.trackCount ?? 0} 首'),
                      trailing: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add),
                      onTap: _busy ? null : () => _addTo(playlist),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
