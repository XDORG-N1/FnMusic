import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../app/services/report/report_html_builder.dart';
import '../../app/services/report/report_snapshot.dart';

/// 听歌报告页：聚合本地听歌数据 → 生成自包含 HTML → WebView 渲染。
///
/// 与参考项目的差异：参考项目加载外部报告网页（hash/localStorage 注入
/// payload）；FnMusic 无外部网页，改用 [ReportHtmlBuilder] 生成内联 CSS
/// 的 HTML 经 `loadHtmlString` 直接渲染，完全离线可用。
class ListeningReportPage extends StatefulWidget {
  const ListeningReportPage({super.key});

  static const String route = '/profile/listening-report';

  @override
  State<ListeningReportPage> createState() => _ListeningReportPageState();
}

enum _ReportStage { building, ready, error }

class _ListeningReportPageState extends State<ListeningReportPage> {
  _ReportStage _stage = _ReportStage.building;
  String? _error;

  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _buildAndOpen();
  }

  Future<void> _buildAndOpen() async {
    setState(() => _stage = _ReportStage.building);
    try {
      final snapshot = await ReportSnapshotBuilder().build();
      final html = ReportHtmlBuilder.build(snapshot);
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF121212))
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              // 自包含 HTML 不应发起站外导航
              return NavigationDecision.prevent;
            },
          ),
        );
      await controller.loadHtmlString(html);
      if (!mounted) return;
      _controller = controller;
      setState(() => _stage = _ReportStage.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _ReportStage.error;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('听歌报告'),
        actions: <Widget>[
          if (_stage == _ReportStage.error)
            TextButton(
              onPressed: _buildAndOpen,
              child: const Text('重试'),
            ),
        ],
      ),
      body: switch (_stage) {
        _ReportStage.building => const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在生成你的听歌报告…'),
              ],
            ),
          ),
        _ReportStage.error => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.error_outline_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  const Text('报告生成失败'),
                  const SizedBox(height: 8),
                  Text(
                    _error ?? '',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _buildAndOpen,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        _ReportStage.ready =>
          _controller == null ? const SizedBox.shrink() : WebViewWidget(controller: _controller!),
      },
    );
  }
}
