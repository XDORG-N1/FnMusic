import 'package:flutter/material.dart';

import '../../app/state/settings_state.dart';

/// 首次启动引导向导（P0 骨架版）。
/// 后续阶段补充外观 / 播放器样式 / 启动行为等步骤。
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<OnboardingStep> _steps = <OnboardingStep>[
    OnboardingStep(
      icon: Icons.music_note,
      title: '欢迎使用飞牛音乐',
      subtitle: '连接你的飞牛私有云 NAS，\n随时随地畅享无损音乐。',
    ),
    OnboardingStep(
      icon: Icons.cloud_outlined,
      title: '云端音乐库',
      subtitle: '曲目、专辑、歌手、歌单自动同步，\n支持 FLAC / DSF 等无损格式。',
    ),
  ];

  Future<void> _finish() async {
    await SettingsOnboarding.setCompleted(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (int value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  return _StepView(step: _steps[index]);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_steps.length, (int index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: index == _page ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: index == _page
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(32),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (_page < _steps.length - 1) {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      );
                    } else {
                      _finish();
                    }
                  },
                  child: Text(_page < _steps.length - 1 ? '下一步' : '开始使用'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingStep {
  const OnboardingStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(step.icon, size: 56, color: scheme.primary),
          ),
          const SizedBox(height: 32),
          Text(
            step.title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            step.subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
