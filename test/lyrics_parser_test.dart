import 'package:flutter_test/flutter_test.dart';
import 'package:fnmusic/app/services/lyrics/lyrics_parser.dart';
import 'package:flutter_lyric/core/lyric_model.dart' as fl;

void main() {
  test('parse translation line with same timestamp', () {
    const lrc = '''
[00:02.392]Ave [00:02.574]Maria [00:04.301]grazia [00:04.589]ricevuta [00:06.145]per [00:06.318]la [00:06.535]mia [00:06.710]famiglia[00:07.285]
[00:02.392]万福玛丽亚 感谢您对于我家族的恩赐[00:15.340]
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    final line = model.lines.firstWhere(
      (l) => l.start == const Duration(milliseconds: 2392),
    );
    expect(
      line.translation,
      '万福玛丽亚 感谢您对于我家族的恩赐',
    );
  });

  test('parse enhanced translation line with same start timestamp', () {
    const lrc = '''
[00:01.000]Hello [00:01.500]world[00:02.000]
[00:01.000]你好[00:01.500]世界[00:02.000]
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    final line = model.lines.firstWhere(
      (l) => l.start == const Duration(seconds: 1),
    );
    expect(line.text, 'Hello world');
    expect(line.translation, '你好世界');
    expect(line.words?.map((w) => w.text).join(), 'Hello world');
  });

  fl.LyricLine lineAt(String lrc, Duration t) {
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    return model.lines.firstWhere((l) => l.start == t);
  }

  test(
    'chinese-original song keeps original as main, foreign as translation',
    () {
      // Same timestamp; original is Han-only, translation is latin. Must NOT swap.
      const lrc = '''
[00:10.00]我们不再联系
[00:10.00]We are no longer in touch
''';
      final line = lineAt(lrc, const Duration(seconds: 10));
      expect(line.text, '我们不再联系');
      expect(line.translation, 'We are no longer in touch');
    },
  );

  test('translation containing latin characters is still detected', () {
    const lrc = '''
[00:12.00]I love you
[00:12.00]我爱你 baby
''';
    final line = lineAt(lrc, const Duration(seconds: 12));
    expect(line.text, 'I love you');
    expect(line.translation, '我爱你 baby');
  });

  test('same-script (zh/zh) translation is detected', () {
    const lrc = '''
[00:05.00]关关雎鸠
[00:05.00]雎鸠鸟关关和唱
''';
    final line = lineAt(lrc, const Duration(seconds: 5));
    expect(line.text, '关关雎鸠');
    expect(line.translation, '雎鸠鸟关关和唱');
  });

  test('near-timestamp translation (rounding) is merged', () {
    const lrc = '''
[00:10.00]I love you
[00:10.01]我爱你
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    expect(model.lines.length, 1);
    expect(model.lines.first.text, 'I love you');
    expect(model.lines.first.translation, '我爱你');
  });

  test('exact-duplicate line is not turned into a translation', () {
    const lrc = '''
[00:03.00]la la la
[00:03.00]la la la
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    final line = model.lines.firstWhere(
      (l) => l.start == const Duration(seconds: 3),
    );
    expect(line.text, 'la la la');
    expect(line.translation, isNull);
  });

  test('offset-timestamp chinese translation is merged (译 button appears)', () {
    // Translation stamped shortly after the original (beyond same-time
    // tolerance) must still fold into the original as its translation.
    const lrc = '''
[00:12.00]あいしてる
[00:12.50]我爱你
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    expect(model.lines.length, 1);
    expect(model.lines.first.text, 'あいしてる');
    expect(model.lines.first.translation, '我爱你');
  });

  test('two consecutive non-chinese lines are NOT merged as translation', () {
    const lrc = '''
[00:12.00]I love you
[00:12.30]So do I
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    expect(model.lines.length, 2);
    expect(model.lines.every((l) => l.translation == null), isTrue);
  });

  test('two consecutive chinese lines are NOT merged as translation', () {
    const lrc = '''
[00:12.00]关关雎鸠
[00:12.20]在河之洲
''';
    final model = LyricsParser.buildModelFromRaw(
      lrc,
      predictDuration: false,
      forceKaraoke: false,
    );
    expect(model.lines.length, 2);
    expect(model.lines.every((l) => l.translation == null), isTrue);
  });

  test('typographic spaces split inline english/chinese translation', () {
    const separators = <String>[
      ' ', // no-break space
      ' ', // four-per-em space
      ' ', // thin space (used by Don't Be So Serious)
      ' ', // narrow no-break space
      '　', // ideographic space
    ];

    for (final separator in separators) {
      final model = LyricsParser.buildModelFromRaw(
        '[00:27.76]Weight$separator沉重\n'
        '[00:30.76]Heavy bones$separator沉重的身体',
        predictDuration: false,
        forceKaraoke: false,
      );

      expect(
        model.lines.length,
        2,
        reason:
            'separator U+'
            '${separator.codeUnitAt(0).toRadixString(16).toUpperCase()}',
      );
      expect(model.lines.first.text, 'Weight');
      expect(model.lines.first.translation, '沉重');
      expect(model.lines.last.text, 'Heavy bones');
      expect(model.lines.last.translation, '沉重的身体');
      expect(
        model.lines.any((line) => (line.translation ?? '').trim().isNotEmpty),
        isTrue,
      );
    }
  });
}
