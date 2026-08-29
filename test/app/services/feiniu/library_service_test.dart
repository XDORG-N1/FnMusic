import 'package:flutter_test/flutter_test.dart';

import 'package:fnmusic/app/services/feiniu/api_client.dart';
import 'package:fnmusic/app/services/feiniu/api_models.dart';
import 'package:fnmusic/app/services/feiniu/library_service.dart';

/// 音乐库管理服务单元测试：不依赖 mock 服务器（本地守卫 / 覆盖钩子）。
void main() {
  setUp(() {
    FnLibraryService.fetchLibrariesOverride = null;
    FnLibraryService.activeScanGuidsOverride = null;
    FnLibraryService.createLibraryOverride = null;
    FnLibraryService.updateLibraryOverride = null;
    FnLibraryService.deleteLibraryOverride = null;
    FnLibraryService.scanLibraryOverride = null;
    FnLibraryService.scanAllLibrariesOverride = null;
    FnLibraryService.rebuildIndexOverride = null;
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
  });

  group('FnLibrary 模型解析', () {
    test('完整字段解析', () {
      final FnLibrary lib = FnLibrary.fromJson(<String, Object?>{
        'guid': 'lib_001',
        'path': '/volume1/media/Music',
        'name': 'NAS 音乐库',
        'autoDownloadLyric': true,
        'metadataPreference': FnMetadataPreference.localOnly,
        'accessStatus': 1,
        'contentLastChangedAt': 1700000000,
        'coverIds': <Object?>['a', ' b ', ''],
      });
      expect(lib.guid, 'lib_001');
      expect(lib.path, '/volume1/media/Music');
      expect(lib.displayName, 'NAS 音乐库');
      expect(lib.autoDownloadLyric, isTrue);
      expect(lib.metadataPreference, FnMetadataPreference.localOnly);
      expect(lib.accessStatus, 1);
      expect(lib.coverIds, <String>['a', 'b']);
    });

    test('displayName 回退到路径末段（name 为空/空白）', () {
      expect(
        FnLibrary.fromJson(<String, Object?>{
          'guid': 'l',
          'path': '/volume1/downloads/音乐',
        }).displayName,
        '音乐',
      );
      expect(
        FnLibrary.fromJson(<String, Object?>{
          'guid': 'l',
          'path': '/a/b/',
          'name': '   ',
        }).displayName,
        'b',
      );
    });

    test('lastChangedAt 归一化：epoch 秒 / 毫秒 / 0', () {
      final FnLibrary sec = FnLibrary.fromJson(<String, Object?>{
        'guid': 'l',
        'path': '/p',
        'contentLastChangedAt': 1700000000,
      });
      expect(sec.lastChangedAt!.millisecondsSinceEpoch, 1700000000000);

      // 服务端回毫秒（>1e12）时归一化为秒。
      final FnLibrary ms = FnLibrary.fromJson(<String, Object?>{
        'guid': 'l',
        'path': '/p',
        'contentLastChangedAt': 1700000000000,
      });
      expect(ms.lastChangedAt!.millisecondsSinceEpoch, 1700000000000);

      // 0 / 缺失 → null（不显示更新于）。
      expect(
        FnLibrary.fromJson(<String, Object?>{'guid': 'l', 'path': '/p'})
            .lastChangedAt,
        isNull,
      );
      expect(
        FnLibrary.fromJson(<String, Object?>{
          'guid': 'l',
          'path': '/p',
          'contentLastChangedAt': 'abc',
        }).lastChangedAt,
        isNull,
      );
    });
  });

  group('FnScanTask 模型解析', () {
    test('ext.libraryGUID 与 isActiveScan 判断', () {
      final FnScanTask active = FnScanTask.fromJson(<String, Object?>{
        'guid': 't1',
        'type': 'fileScan',
        'done': false,
        'cancelling': false,
        'createdAt': 1700000000,
        'ext': <String, Object?>{'libraryGUID': 'lib_001'},
      });
      expect(active.libraryGuid, 'lib_001');
      expect(active.isActiveScan, isTrue);

      // 已完成 → 非活跃。
      final FnScanTask done = FnScanTask.fromJson(<String, Object?>{
        'guid': 't2',
        'type': 'fileScan',
        'done': true,
        'cancelling': false,
        'createdAt': 1,
        'ext': <String, Object?>{'libraryGUID': 'lib_001'},
      });
      expect(done.isActiveScan, isFalse);

      // 非 fileScan 类型 → 非活跃。
      final FnScanTask other = FnScanTask.fromJson(<String, Object?>{
        'guid': 't3',
        'type': 'transcode',
        'done': false,
        'cancelling': false,
        'createdAt': 1,
      });
      expect(other.isActiveScan, isFalse);
    });
  });

  group('本地守卫（不发起网络请求）', () {
    test('createLibrary 空路径 → 100002', () async {
      await expectLater(
        FnLibraryService.instance.createLibrary(path: '   '),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
    });

    test('updateLibrary 空 guid / 空路径 → 100002', () async {
      await expectLater(
        FnLibraryService.instance
            .updateLibrary(guid: '  ', path: '/p'),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
      await expectLater(
        FnLibraryService.instance
            .updateLibrary(guid: 'lib_1', path: ''),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
    });

    test('deleteLibrary / scanLibrary 空 guid → 100002', () async {
      await expectLater(
        FnLibraryService.instance.deleteLibrary(''),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
      await expectLater(
        FnLibraryService.instance.scanLibrary('   '),
        throwsA(isA<ApiException>()
            .having((ApiException e) => e.code, 'code', 100002)),
      );
    });
  });

  group('覆盖钩子行为', () {
    test('fetchLibraries 走覆盖钩子', () async {
      final List<FnLibrary> libs = <FnLibrary>[
        FnLibrary.fromJson(<String, Object?>{
          'guid': 'lib_x',
          'path': '/p/x',
          'name': 'X',
        }),
      ];
      FnLibraryService.fetchLibrariesOverride = () async => libs;
      expect(await FnLibraryService.instance.fetchLibraries(), libs);
    });

    test('activeScanLibraryGuids 走覆盖钩子', () async {
      FnLibraryService.activeScanGuidsOverride = () async =>
          <String>{'lib_001'};
      expect(
        await FnLibraryService.instance.activeScanLibraryGuids(),
        <String>{'lib_001'},
      );
    });

    test('createLibrary 走覆盖钩子并透传参数', () async {
      String? seenPath;
      String? seenPref;
      bool? seenLyric;
      FnLibraryService.createLibraryOverride = ({
        required String path,
        String metadataPreference = FnMetadataPreference.cloudPreferred,
        bool autoDownloadLyric = false,
      }) async {
        seenPath = path;
        seenPref = metadataPreference;
        seenLyric = autoDownloadLyric;
      };
      await FnLibraryService.instance.createLibrary(
        path: '  /volume1/music  ',
        metadataPreference: FnMetadataPreference.localOnly,
        autoDownloadLyric: true,
      );
      expect(seenPath, '/volume1/music');
      expect(seenPref, FnMetadataPreference.localOnly);
      expect(seenLyric, isTrue);
    });

    test('updateLibrary / deleteLibrary / scan / scanAll / rebuild 走覆盖钩子',
        () async {
      String? deletedGuid;
      String? scannedGuid;
      bool scanAllCalled = false;
      bool rebuildCalled = false;
      FnLibraryService.deleteLibraryOverride = (String g) async {
        deletedGuid = g;
      };
      FnLibraryService.scanLibraryOverride = (String g) async {
        scannedGuid = g;
      };
      FnLibraryService.scanAllLibrariesOverride = () async {
        scanAllCalled = true;
      };
      FnLibraryService.rebuildIndexOverride = () async {
        rebuildCalled = true;
      };

      await FnLibraryService.instance.deleteLibrary('lib_9');
      expect(deletedGuid, 'lib_9');

      await FnLibraryService.instance.scanLibrary('lib_8');
      expect(scannedGuid, 'lib_8');

      await FnLibraryService.instance.scanAllLibraries();
      expect(scanAllCalled, isTrue);

      await FnLibraryService.instance.rebuildSearchIndex();
      expect(rebuildCalled, isTrue);
    });
  });
}
