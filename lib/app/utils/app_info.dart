/// 应用信息常量（保持与 pubspec.yaml version 一致）。
///
/// 独立成文件供页面与备份等纯 Dart 服务共用；
/// 不依赖 package_info_plus（不在离线 pub cache，版本为硬编码常量）。
abstract class AppInfo {
  static const String name = 'FnMusic';
  static const String displayName = '飞牛音乐';
  static const String version = '1.0.0+1';
}
