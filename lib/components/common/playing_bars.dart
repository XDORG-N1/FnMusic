import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 三根随播放状态起伏的迷你音量条（播放中动画，暂停静止）。
class PlayingBars extends StatefulWidget {
  final Color color;
  final bool animating;

  const PlayingBars({super.key, required this.color, required this.animating});

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    if (widget.animating) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant PlayingBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animating && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animating && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double value = _controller.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List<Widget>.generate(3, (int index) {
              final double height;
              if (widget.animating) {
                final double phase = (value + index / 3) % 1.0;
                final double scale = 0.5 - 0.5 * math.cos(2 * math.pi * phase);
                height = 4 + 10 * scale;
              } else {
                height = 8;
              }
              return Container(
                width: 3,
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
