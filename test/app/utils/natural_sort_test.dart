import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/utils/natural_sort.dart';
import 'package:fnmusic/components/common/alphabet_indexer.dart';

void main() {
  group('NaturalSort.compare', () {
    test('数字按数值比较而非字典序', () {
      expect(NaturalSort.compare('第2首', '第10首'), lessThan(0));
      expect(NaturalSort.compare('第10首', '第2首'), greaterThan(0));
    });

    test('中文按拼音排序', () {
      // '安'(an) < '北'(bei) < '陈'(chen)
      expect(NaturalSort.compare('安', '北'), lessThan(0));
      expect(NaturalSort.compare('北', '陈'), lessThan(0));
      expect(NaturalSort.compare('陈', '安'), greaterThan(0));
    });

    test('英文忽略大小写', () {
      expect(NaturalSort.compare('abc', 'ABC'), 0);
      expect(NaturalSort.compare('apple', 'banana'), lessThan(0));
    });

    test('空串兜底靠前', () {
      expect(NaturalSort.compare('', 'a'), lessThan(0));
    });
  });

  group('IndexUtils.leadingLetter', () {
    test('英文取首字母', () {
      expect(IndexUtils.leadingLetter('Apple'), 'A');
      expect(IndexUtils.leadingLetter('the cure'), 'T');
    });

    test('数字归为 0', () {
      expect(IndexUtils.leadingLetter('12345 演唱会'), '0');
      expect(IndexUtils.leadingLetter('2Pac'), '0');
    });

    test('中文取拼音首字母', () {
      expect(IndexUtils.leadingLetter('林晚风'), 'L');
      expect(IndexUtils.leadingLetter('周杰伦'), 'Z');
    });

    test('空串 / 符号兜底为 #', () {
      expect(IndexUtils.leadingLetter(''), '#');
      expect(IndexUtils.leadingLetter('   '), '#');
      expect(IndexUtils.leadingLetter('…'), '#');
    });
  });

  group('IndexUtils.nearestIndexForLetter', () {
    test('直接命中返回索引', () {
      final map = <String, int>{'A': 0, 'C': 5};
      expect(IndexUtils.nearestIndexForLetter('A', IndexUtils.defaultLetters(), map), 0);
    });

    test('未命中向邻近字母扩散', () {
      final map = <String, int>{'A': 0, 'C': 5};
      // B 未命中，向后找到 C 的索引。
      expect(IndexUtils.nearestIndexForLetter('B', IndexUtils.defaultLetters(), map), 5);
      // Z 未命中，向前扩散。
      expect(IndexUtils.nearestIndexForLetter('Z', IndexUtils.defaultLetters(), map), 5);
    });
  });
}
