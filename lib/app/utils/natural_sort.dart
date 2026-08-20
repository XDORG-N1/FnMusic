import 'package:lpinyin/lpinyin.dart';

/// 自然排序：数字按数值比较，中文转拼音（忽略大小写）。
/// 用于歌曲/专辑/歌手列表的排序与索引。
class NaturalSort {
  NaturalSort._();

  static final RegExp _numberChunk = RegExp(r'\d+');

  /// 比较器：`list.sort(NaturalSort.compare)`。
  static int compare(String a, String b) {
    return _compareChunks(
      _tokenize(a.trim().toLowerCase()),
      _tokenize(b.trim().toLowerCase()),
    );
  }

  /// 获取排序键（便于排序后分组索引）。
  static String sortKey(String text) {
    final String lower = text.trim().toLowerCase();
    if (lower.isEmpty) return '#';
    final String pinyin = PinyinHelper.getPinyinE(lower, separator: '');
    final String first = pinyin.isNotEmpty ? pinyin[0] : '#';
    if (RegExp(r'[a-z]').hasMatch(first)) return first.toUpperCase();
    return '#';
  }

  static List<Object> _tokenize(String s) {
    final List<Object> tokens = <Object>[];
    final Iterable<Match> matches = _numberChunk.allMatches(s);
    int cursor = 0;
    for (final Match m in matches) {
      if (m.start > cursor) {
        final String text = s.substring(cursor, m.start);
        tokens.add(_pinyin(text));
      }
      tokens.add(int.parse(m.group(0)!));
      cursor = m.end;
    }
    if (cursor < s.length) {
      tokens.add(_pinyin(s.substring(cursor)));
    }
    return tokens;
  }

  static String _pinyin(String text) {
    if (text.isEmpty) return '';
    if (RegExp(r'[一-鿿]').hasMatch(text)) {
      return PinyinHelper.getPinyinE(text, separator: '', defPinyin: text);
    }
    return text;
  }

  static int _compareChunks(List<Object> a, List<Object> b) {
    final int len = a.length < b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      final Object x = a[i];
      final Object y = b[i];
      if (x is int && y is int) {
        if (x != y) return x - y;
      } else {
        final int c = x.toString().compareTo(y.toString());
        if (c != 0) return c;
      }
    }
    return a.length - b.length;
  }
}
