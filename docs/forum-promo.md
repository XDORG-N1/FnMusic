# 飞牛 NAS 音乐客户端 FnMusic —— 把 NAS 音乐库装进口袋（v1.0.5 已发布）

你是否有一个装满音乐的 NAS，却一直找不到一个顺手、好看、能用的手机端音乐播放器？

**FnMusic** 来了 —— 由 **XDORG 团队自主研发**，一个专为飞牛 FNOS 打造的原生音乐客户端（Android 15+）。界面清爽、体验流畅，把你的 NAS 音乐库变成随身曲库。**Apache-2.0 完全开源**，已发布 v1.0.5。

## 它能做什么

### 🎧 登录即听
- 支持 **FN ID / FN Connect 登录**，自动探测可达地址（内网 → 公网 → 中继），无需手动折腾端口和穿透
- 连接信息与账号安全保存，重启自动恢复会话

### 🏠 首页仪表盘
- 漫游 Hero、我的收藏、最近播放、歌单、最新歌曲、最新专辑一屏尽览
- 本地缓存 + 下拉刷新，断网也能看到上次的推荐

### ▶️ 播放体验
- 双引擎播放（just_audio / media_kit），自动回退转码，冷门格式也能放
- 唯一播放队列、倍速播放、睡眠定时
- 全屏播放器 + 迷你播放器，下拉即可收起
- **歌词同步**：卡拉 OK 逐字高亮 + 翻译显示

### 📻 系统级联动
- 媒体通知、锁屏控制
- **Android Auto 车载**：开车时也能安全浏览与播放 NAS 音乐

### 🗂️ 资料库管理
- 专辑 / 歌手 / 风格浏览，搜索全网曲目
- 收藏、歌单管理、听歌统计与**听歌报告**
- 备份恢复：本地 + WebDAV，换机不丢数据

### ✨ v1.0.5 新增
- **音乐库路径选择器**：设置音乐库「音乐文件夹」时，路径改为**点击式文件夹选择器**，与网页版设置页交互完全对齐——面包屑逐级浏览授权目录、语义化展示路径（存储空间 / 我的文件 / 应用文件 / 外接存储 / 他人共享 / 远程挂载），已添加为音乐库的文件夹自动标注「已添加」且不可重复选择，选路径从此不用手敲、不会敲错
- 底层对接 FNOS 真实授权目录接口（app-center authed-dir），与飞牛官方 Web 端行为一致

### 🛡️ 健壮与省心
- 会话失效自动回退登录页，绝不「卡死半登录」
- 支持退出登录，多账号切换不串台
- 兼容企业网关 SSL 重签环境

## 快速上手

1. 下载安装 APK（见下方链接）
2. 打开后输入 FN Connect 账号（或 NAS 地址 + 用户名 + 密码）
3. 享受你的 NAS 曲库

> 仅支持 **Android 15+**（minSdk 35）。

## 下载

- **GitHub 仓库**：<https://github.com/XDORG-N1/FnMusic>
- **最新版 APK**（始终指向最新 release）：<https://github.com/XDORG-N1/FnMusic/releases/latest>
- **v1.0.5 直链**：<https://github.com/XDORG-N1/FnMusic/releases/download/v1.0.5/app-release.apk>

下载后开启「允许安装未知来源应用」即可安装。

## 一起参与，让 FnMusic 更好 💪

FnMusic 是开源的，属于每一位热爱 NAS 音乐的人：

- ⭐ **点个 Star**：你的点赞是对我们最大的鼓励，也能让更多人看到这个项目；
- 🐛 **反馈问题**：遇到任何 bug 或使用不便，请到 GitHub [Issues](https://github.com/XDORG-N1/FnMusic/issues) 提出来，附上复现步骤更佳；
- 🛠️ **加入开发**：Fork 项目 → 建分支 → 提 PR（`flutter analyze` + `flutter test` 全绿即可）→ 我们认真 review 并合并；
- 📝 **贡献想法**：功能建议、UI 优化、文档翻译……任何形式的参与都欢迎；
- 📖 完整的开源策略（许可证、维护模型、贡献约定、路线图）见 [docs/opensource-strategy.md](https://github.com/XDORG-N1/FnMusic/blob/main/docs/opensource-strategy.md)。

> 本项目由 **XDORG 团队自主研发**，基于 **Apache License 2.0** 开源（Copyright © 2026 XDORG）。

让 NAS 里的音乐，真正属于你的口袋。🎵 Star ⭐ 一下，加入我们一起玩吧！
