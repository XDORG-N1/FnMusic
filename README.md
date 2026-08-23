# FnMusic 🎵

**飞牛 NAS（FNOS）音乐客户端** · 面向 Android 15+ 的原生音乐播放器。

把你的 NAS 音乐库装进口袋 —— 登录即听，界面清爽，功能完整。

## 特性

- **FN ID / FN Connect 登录**：自动探测可达地址（内网 → 公网 → 中继），无需手动穿透
- **首页仪表盘**：漫游 Hero、收藏、最近播放、歌单、最新歌曲、最新专辑，本地缓存 + 下拉刷新
- **播放核心**：双引擎（just_audio / media_kit）自动回退转码、唯一播放队列、倍速、睡眠定时
- **播放器 UI**：全屏播放器、迷你播放器、卡拉 OK 歌词 + 翻译
- **系统联动**：媒体通知、锁屏控制、Android Auto 车载浏览播放
- **资料库管理**：专辑 / 歌手 / 流派 / 搜索、收藏、歌单、听歌统计与听歌报告
- **备份恢复**：本地 + WebDAV，换机不丢数据
- **健壮省心**：会话失效自动回退登录页、退出登录、缓存管理、兼容企业网关 SSL 重签环境

## 下载

最新版 APK 已发布到 GitHub Releases：

- **GitHub 仓库**：<https://github.com/XDORG-N1/FnMusic>
- **最新版 APK**：<https://github.com/XDORG-N1/FnMusic/releases/latest>

安装时需开启「允许安装未知来源应用」。

> 仅支持 **Android 15+**（minSdk 35）。

## 从源码构建

```bash
# 需要 Flutter 3.x（本项目基于 Flutter 3.47）
flutter pub get
flutter build apk --release
```

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

运行测试：

```bash
flutter analyze
flutter test
```

## 反馈

任何问题、建议或功能需求，欢迎在 [Issues](https://github.com/XDORG-N1/FnMusic/issues) 提出。
