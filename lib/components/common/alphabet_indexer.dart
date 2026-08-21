import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';

/// 拼音/首字母工具：用于列表的字母索引分组与定位。
class IndexUtils {
  /// 取文本的首字母（A–Z / '0' 数字 / '#' 兜底）。
  ///
  /// 与 [NaturalSort] 的分组键口径一致：英文取首字母，数字归 '0'，
  /// 中文取拼音首字母（lpinyin），其余归 '#'。
  static String leadingLetter(String text) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return '#';

    final String firstChar = trimmed.substring(0, 1).toUpperCase();
    if (RegExp(r'[A-Z]').hasMatch(firstChar)) {
      return firstChar;
    }

    if (RegExp(r'[0-9]').hasMatch(firstChar)) {
      return '0';
    }

    final String pinyin = PinyinHelper.getFirstWordPinyin(trimmed);
    if (pinyin.isNotEmpty) {
      final String pinyinFirst = pinyin.substring(0, 1).toUpperCase();
      if (RegExp(r'[A-Z]').hasMatch(pinyinFirst)) {
        return pinyinFirst;
      }
    }

    return '#';
  }

  /// 索引条字母集合：数字 '0' + A–Z + '#'
  static List<String> defaultLetters() {
    final List<String> letters = <String>['0'];
    for (var i = 0; i < 26; i++) {
      letters.add(String.fromCharCode(65 + i));
    }
    letters.add('#');
    return letters;
  }

  /// 命中字母的直接索引；无则向附近字母扩散查找最近存在的索引。
  static int? nearestIndexForLetter(
    String letter,
    List<String> letters,
    Map<String, int> indexMap,
  ) {
    final int? direct = indexMap[letter];
    if (direct != null) return direct;
    final int start = letters.indexOf(letter);
    if (start == -1) return null;
    for (var i = start + 1; i < letters.length; i++) {
      final int? idx = indexMap[letters[i]];
      if (idx != null) return idx;
    }
    for (var i = start - 1; i >= 0; i--) {
      final int? idx = indexMap[letters[i]];
      if (idx != null) return idx;
    }
    return null;
  }
}

/// 右侧字母索引条：按下/拖动实时上报字母。
class AlphabetIndexBar extends StatelessWidget {
  final List<String> letters;
  final void Function(String letter) onLetterSelected;

  const AlphabetIndexBar({
    super.key,
    required this.letters,
    required this.onLetterSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double itemHeight = letters.isEmpty
            ? constraints.maxHeight
            : (constraints.maxHeight / letters.length).clamp(12.0, 28.0);
        int indexFromDy(double dy) {
          return (dy / itemHeight).floor().clamp(0, letters.length - 1);
        }

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) {
            final int idx = indexFromDy(details.localPosition.dy);
            onLetterSelected(letters[idx]);
          },
          onPanUpdate: (details) {
            final int idx = indexFromDy(details.localPosition.dy);
            onLetterSelected(letters[idx]);
          },
          child: SizedBox(
            width: 24,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: letters
                  .map(
                    (String letter) => SizedBox(
                      height: itemHeight,
                      child: Center(
                        child: Text(
                          letter,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

/// 拖动索引条时浮出的字母预览。
class IndexPreview extends StatelessWidget {
  final String text;
  final bool visible;

  const IndexPreview({
    super.key,
    required this.text,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(right: 36),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  text,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表右侧可拖动的滚动条：拖动定位到目标条目并回调其索引标签。
class DraggableScrollbar extends StatelessWidget {
  final ScrollController controller;
  final int itemCount;
  final double itemExtent;
  final String Function(int index) getLabel;
  final ValueChanged<String> onIndexChanged;
  final VoidCallback onDragEnd;

  /// 自定义跳转（网格列表用：`itemExtent` 跳转不适用，由调用方计算行偏移）。
  /// 提供时替代默认的 `controller.jumpTo(targetIndex * itemExtent)`。
  final ValueChanged<int>? onScrollRequest;

  const DraggableScrollbar({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemExtent,
    required this.getLabel,
    required this.onIndexChanged,
    required this.onDragEnd,
    this.onScrollRequest,
  });

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (details) {},
          onVerticalDragUpdate: (details) {
            _handleDrag(details.localPosition.dy, totalHeight);
          },
          onVerticalDragEnd: (_) => onDragEnd(),
          onVerticalDragCancel: onDragEnd,
          child: SizedBox(
            width: 24,
            height: totalHeight,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                if (!controller.hasClients) return const SizedBox.shrink();

                final double maxScroll = controller.position.maxScrollExtent;
                if (maxScroll <= 0) return const SizedBox.shrink();

                final double currentScroll =
                    controller.offset.clamp(0.0, maxScroll);
                final double scrollFraction = currentScroll / maxScroll;

                final double viewPort = controller.position.viewportDimension;
                final double contentHeight = maxScroll + viewPort;
                final double thumbHeight =
                    (viewPort / contentHeight * totalHeight)
                        .clamp(40.0, totalHeight);

                final double availableSlide = totalHeight - thumbHeight;
                final double thumbTop = scrollFraction * availableSlide;

                return Stack(
                  children: <Widget>[
                    Positioned(
                      top: thumbTop,
                      right: 4,
                      child: Container(
                        width: 4,
                        height: thumbHeight,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _handleDrag(double dy, double totalHeight) {
    if (itemCount == 0) return;

    final double clampedDy = dy.clamp(0.0, totalHeight);
    final double fraction = clampedDy / totalHeight;

    final int targetIndex =
        (fraction * (itemCount - 1)).floor().clamp(0, itemCount - 1);

    final ValueChanged<int>? custom = onScrollRequest;
    if (custom != null) {
      custom(targetIndex);
    } else {
      if (!controller.hasClients) return;
      final double maxScroll = controller.position.maxScrollExtent;
      if (maxScroll <= 0) return;
      final double offset = (targetIndex * itemExtent).clamp(0.0, maxScroll);
      controller.jumpTo(offset);
    }

    final String label = getLabel(targetIndex);
    onIndexChanged(label);
  }
}
