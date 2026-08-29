import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/library_service.dart';
import 'package:fnmusic/pages/library/library_manage_page.dart';

FnLibrary _lib(
  String guid,
  String path, {
  String name = '',
  String pref = FnMetadataPreference.cloudPreferred,
  bool autoDownloadLyric = false,
  int changedAt = 0,
}) {
  return FnLibrary.fromJson(<String, Object?>{
    'guid': guid,
    'path': path,
    'name': name,
    'metadataPreference': pref,
    'autoDownloadLyric': autoDownloadLyric,
    'contentLastChangedAt': changedAt,
  });
}

/// 文件夹选择器目录树（根 key 为 `''`）。
Map<String, List<FnDirectory>> _dirTree() {
  return <String, List<FnDirectory>>{
    '': const <FnDirectory>[
      FnDirectory(path: '/vol1', name: 'volume1', storageType: 3),
      FnDirectory(path: '/vol00', name: '外接存储', storageType: 0),
    ],
    '/vol1': const <FnDirectory>[
      FnDirectory(path: '/vol1/media', name: 'media'),
      FnDirectory(path: '/vol1/downloads', name: 'downloads'),
    ],
    '/vol1/media': const <FnDirectory>[
      FnDirectory(path: '/vol1/media/Music', name: 'Music'),
      FnDirectory(path: '/vol1/media/Movies', name: 'Movies'),
    ],
    '/vol1/media/Movies': const <FnDirectory>[],
  };
}

/// 装配文件夹选择器覆盖钩子。
void _stubDirTree(Map<String, List<FnDirectory>> tree) {
  FnLibraryService.fetchAuthorizedDirectoriesOverride = () async =>
      tree[''] ?? const <FnDirectory>[];
  FnLibraryService.fetchSubDirectoriesOverride = (String parent) async =>
      tree[parent] ?? const <FnDirectory>[];
}

void main() {
  List<FnLibrary> libs = <FnLibrary>[];
  Set<String> scanning = <String>{};

  setUp(() {
    libs = <FnLibrary>[];
    scanning = <String>{};
    FnLibraryService.fetchLibrariesOverride = null;
    FnLibraryService.activeScanGuidsOverride = null;
    FnLibraryService.createLibraryOverride = null;
    FnLibraryService.updateLibraryOverride = null;
    FnLibraryService.deleteLibraryOverride = null;
    FnLibraryService.scanLibraryOverride = null;
    FnLibraryService.scanAllLibrariesOverride = null;
    FnLibraryService.rebuildIndexOverride = null;
    FnLibraryService.fetchAuthorizedDirectoriesOverride = null;
    FnLibraryService.fetchSubDirectoriesOverride = null;
  });

  tearDown(() {
    FnLibraryService.fetchLibrariesOverride = null;
    FnLibraryService.activeScanGuidsOverride = null;
    FnLibraryService.createLibraryOverride = null;
    FnLibraryService.updateLibraryOverride = null;
    FnLibraryService.deleteLibraryOverride = null;
    FnLibraryService.scanLibraryOverride = null;
    FnLibraryService.scanAllLibrariesOverride = null;
    FnLibraryService.rebuildIndexOverride = null;
    FnLibraryService.fetchAuthorizedDirectoriesOverride = null;
    FnLibraryService.fetchSubDirectoriesOverride = null;
  });

  /// 装配页面：列表与扫描状态均走覆盖钩子。
  Future<void> pumpPage(WidgetTester tester) async {
    FnLibraryService.fetchLibrariesOverride = () async =>
        List<FnLibrary>.of(libs);
    FnLibraryService.activeScanGuidsOverride = () async =>
        Set<String>.of(scanning);
    await tester.pumpWidget(const MaterialApp(home: LibraryManagePage()));
    await tester.pumpAndSettle();
  }

  testWidgets('渲染音乐库卡片：名称 + 路径 + 更新于 + 动作按钮', (WidgetTester tester) async {
    libs = <FnLibrary>[
      _lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库', changedAt: 1700000000),
      _lib('lib_002', '/vol1/downloads/音乐'),
    ];
    await pumpPage(tester);

    expect(find.text('NAS 音乐库'), findsOneWidget);
    expect(find.text('/vol1/media/Music'), findsOneWidget);
    expect(find.text('/vol1/downloads/音乐'), findsOneWidget);
    // 无 name 时回退路径末段。
    expect(find.text('音乐'), findsWidgets);
    expect(find.textContaining('更新于'), findsOneWidget);
    expect(find.byTooltip('编辑'), findsNWidgets(2));
    expect(find.byTooltip('扫描'), findsNWidgets(2));
    expect(find.byTooltip('删除'), findsNWidgets(2));
  });

  testWidgets('扫描中的音乐库显示「扫描中」徽章且扫描按钮禁用', (WidgetTester tester) async {
    libs = <FnLibrary>[_lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库')];
    scanning = <String>{'lib_001'};
    FnLibraryService.fetchLibrariesOverride = () async => libs;
    FnLibraryService.activeScanGuidsOverride = () async => scanning;
    await tester.pumpWidget(const MaterialApp(home: LibraryManagePage()));
    // 扫描中卡片带不定进度圈（持续动画），不能用 pumpAndSettle。
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('扫描中'), findsOneWidget);
    // 扫描中 → 扫描按钮禁用：点击不应触发 scanLibrary。
    bool scanCalled = false;
    FnLibraryService.scanLibraryOverride = (String guid) async {
      scanCalled = true;
    };
    await tester.tap(find.byTooltip('扫描'));
    await tester.pump();
    expect(scanCalled, isFalse);
  });

  testWidgets('空列表显示空态提示', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(find.text('暂无音乐库'), findsOneWidget);
    expect(find.text('添加音乐库'), findsOneWidget);
  });

  testWidgets('加载失败显示友好错误并可重试', (WidgetTester tester) async {
    int calls = 0;
    FnLibraryService.fetchLibrariesOverride = () async {
      calls++;
      if (calls == 1) throw ApiException(100002, '');
      return <FnLibrary>[_lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库')];
    };
    FnLibraryService.activeScanGuidsOverride = () async => <String>{};
    await tester.pumpWidget(const MaterialApp(home: LibraryManagePage()));
    await tester.pumpAndSettle();

    expect(find.text('参数不完整或格式不正确'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('NAS 音乐库'), findsOneWidget);
  });

  testWidgets('添加音乐库：空路径校验 + 文件夹选择器 + 提交 create 并刷新', (WidgetTester tester) async {
    libs = <FnLibrary>[_lib('lib_001', '/vol1/media/Existing', name: 'NAS 音乐库')];
    _stubDirTree(_dirTree());
    String? createdPath;
    String? createdPref;
    bool? createdLyric;
    FnLibraryService.createLibraryOverride = ({
      required String path,
      String metadataPreference = FnMetadataPreference.cloudPreferred,
      bool autoDownloadLyric = false,
    }) async {
      createdPath = path;
      createdPref = metadataPreference;
      createdLyric = autoDownloadLyric;
      libs.add(_lib('lib_new', path,
          name: '新音乐库',
          pref: metadataPreference,
          autoDownloadLyric: autoDownloadLyric));
    };
    await pumpPage(tester);

    await tester.tap(find.text('添加音乐库'));
    await tester.pumpAndSettle();
    expect(find.text('添加音乐库'), findsNWidgets(2)); // FAB + 对话框标题

    // 空路径 → 本地校验错误，不提交。
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('请选择文件夹路径'), findsOneWidget);
    expect(createdPath, isNull);

    // 打开文件夹选择器 → 顶层授权目录（语义化标签）。
    await tester.tap(find.text('请选择文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('选择文件夹'), findsOneWidget);
    expect(find.text('存储空间 1'), findsOneWidget);
    expect(find.text('外接存储'), findsOneWidget);

    // 逐级进入 /vol1 → media → Music，选择此文件夹。
    await tester.tap(find.text('存储空间 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('media'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();

    // 字段回填语义化路径。
    expect(find.text('存储空间 1/media/Music'), findsOneWidget);

    // 选「仅本地」+ 开启自动下载歌词。
    await tester.tap(find.text('仅本地'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(createdPath, '/vol1/media/Music');
    expect(createdPref, FnMetadataPreference.localOnly);
    expect(createdLyric, isTrue);
    // 列表已刷新。
    expect(find.text('新音乐库'), findsOneWidget);
  });

  testWidgets('编辑音乐库：预填语义化路径，选择器禁用已添加文件夹', (WidgetTester tester) async {
    libs = <FnLibrary>[_lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库')];
    _stubDirTree(_dirTree());
    String? editedGuid;
    String? editedPath;
    FnLibraryService.updateLibraryOverride = ({
      required String guid,
      required String path,
      String metadataPreference = FnMetadataPreference.cloudPreferred,
      bool autoDownloadLyric = false,
    }) async {
      editedGuid = guid;
      editedPath = path;
    };
    await pumpPage(tester);

    await tester.tap(find.byTooltip('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑音乐库'), findsOneWidget);
    // 预填：字段显示语义化路径。
    expect(find.text('存储空间 1/media/Music'), findsOneWidget);

    // 打开选择器 → /vol1 → media：Music 已添加（禁用），同级换选 Movies。
    await tester.tap(find.text('存储空间 1/media/Music'));
    await tester.pumpAndSettle();
    expect(find.text('选择文件夹'), findsOneWidget);
    await tester.tap(find.text('存储空间 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('media'));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);

    await tester.tap(find.text('Movies'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择此文件夹'));
    await tester.pumpAndSettle();
    expect(find.text('存储空间 1/media/Movies'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(editedGuid, 'lib_001');
    expect(editedPath, '/vol1/media/Movies');
  });

  testWidgets('删除音乐库：取消不删，确认调用 delete 并移除', (WidgetTester tester) async {
    libs = <FnLibrary>[
      _lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库'),
      _lib('lib_002', '/vol1/downloads/音乐'),
    ];
    String? deletedGuid;
    FnLibraryService.deleteLibraryOverride = (String guid) async {
      deletedGuid = guid;
      libs.removeWhere((FnLibrary l) => l.guid == guid);
    };
    await pumpPage(tester);

    // 第一张卡片删除按钮。
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    expect(find.text('删除音乐库'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(deletedGuid, isNull);
    expect(find.text('NAS 音乐库'), findsOneWidget);

    // 再次删除并确认。
    await tester.tap(find.byTooltip('删除').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deletedGuid, 'lib_001');
    expect(find.text('NAS 音乐库'), findsNothing);
  });

  testWidgets('扫描音乐库调用 scan 并轮询扫描状态', (WidgetTester tester) async {
    libs = <FnLibrary>[_lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库')];
    String? scannedGuid;
    FnLibraryService.scanLibraryOverride = (String guid) async {
      scannedGuid = guid;
    };
    await pumpPage(tester);

    await tester.tap(find.byTooltip('扫描'));
    await tester.pumpAndSettle();
    expect(scannedGuid, 'lib_001');

    // 推进 3s 触发一次轮询；覆盖返回空集合 → 定时器自取消。
    scanning = <String>{};
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
  });

  testWidgets('扫描全部 + 重建索引走对应覆盖钩子', (WidgetTester tester) async {
    libs = <FnLibrary>[_lib('lib_001', '/vol1/media/Music', name: 'NAS 音乐库')];
    bool scanAllCalled = false;
    bool rebuildCalled = false;
    FnLibraryService.scanAllLibrariesOverride = () async {
      scanAllCalled = true;
    };
    FnLibraryService.rebuildIndexOverride = () async {
      rebuildCalled = true;
    };
    await pumpPage(tester);

    await tester.tap(find.byTooltip('扫描全部'));
    await tester.pumpAndSettle();
    expect(scanAllCalled, isTrue);

    // 推进 3s 触发轮询自取消。
    scanning = <String>{};
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    await tester.tap(find.byTooltip('重建搜索索引'));
    await tester.pumpAndSettle();
    expect(rebuildCalled, isTrue);
  });
}
