/// 车载蓝牙歌词：开启且为当前歌曲时，返回要写入 `MediaItem.title` 的歌词行。
/// 返回 `null` 表示不覆盖（车机显示真实歌名）。
///
/// AVRCP 只把 TITLE / ARTIST / ALBUM / TRACK_NUMBER / NUM_TRACKS / GENRE /
/// DURATION 等标准属性发给车机，`METADATA_KEY_LYRICS` 不会到达车机（AOSP
/// `avrcp/helpers/Util.java` 的 `bundleToMetadata` 只读这 7 个 key）。因此用
/// `title` 携带当前歌词行，让车机在 TITLE 位置显示歌词。
String? carLyricsTitleOverride({
  required bool carLyricsEnabled,
  required bool isCurrentSong,
  required String? currentCarLyricLine,
}) {
  if (!carLyricsEnabled || !isCurrentSong) return null;
  final line = currentCarLyricLine?.trim() ?? '';
  return line.isEmpty ? null : line;
}
