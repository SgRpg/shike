# 拾刻

把此刻轻轻拾起。一个只在本机保存记录的温馨日记 App，提供安卓彩蛋版和无彩蛋简版。

## 安卓安装包

支持 Android 8.0 及以上的 ARM 手机。下载 APK 后，按手机提示允许对应来源安装即可，无需每周续签。

| 版本 | 安装包 | 主要区别 |
| --- | --- | --- |
| 彩蛋版 1.0.2 | [下载彩蛋版 APK](https://github.com/SgRpg/shike/releases/download/android-20261102/shike-rewards-1.0.2-android.apk) | 保留彩蛋、卡包和低心情提示；公开包不含私人照片素材 |
| 简版 1.0.2 | [下载简版 APK](https://github.com/SgRpg/shike/releases/download/android-20261102/shike-plain-1.0.2-android.apk) | 去掉彩蛋和卡包，保留低心情提示 |

[查看本次发布与全部安装包](https://github.com/SgRpg/shike/releases/tag/android-20261102)

两版都保留日记、草稿、拾影、时间胶囊、句子引用、心情图表、天气、备份迁移及关于页故事。彩蛋版的私人照片素材不上传仓库或 Releases；公开包缺少可用照片时会跳过照片卡，之后不追补。

两个版本在手机上均显示为“拾刻”。两版可同时安装，数据相互独立。需要带入另一版的日记时，请先导出备份，再在目标版本导入。更新同一版本系列时直接覆盖安装，请勿先卸载。

安装包已完成正式签名构建，真机权限、通知和双机迁移仍待实际验收。

## 仓库源码与 iOS 构建

Flutter 工程位于 `shike_ios/`。正式入口为 `lib/main.dart`，独立完整版入口为 `lib/complete_main.dart`。明确指定 `--dart-define=SHIKE_VISUAL_DEMO=true` 才使用演示数据。

```text
cd shike_ios
flutter pub get
flutter analyze
flutter test
flutter run -t lib/complete_main.dart
```

保留了确认后的暖白、蓝灰及六色心情样式。完整版增加事务保存、草稿位置、句子引用、胶囊状态、彩蛋事件、备份合并及 iOS 本地能力。私人照片素材未随源码提供，缺图机会跳过且不追补。

根目录 `codemagic.yaml` 提供手动触发的未签名 iOS 构建。Windows 工具 `tools/ios_delivery.py` 用于源码白名单导出、安装包打包及签名前注入私人素材。无需账号服务或日记云同步。

当前自动化和网页构建结果见 `docs/complete-ios/ACCEPTANCE.md`。2026-10-28 已完成云端 iOS 编译，源码提交 ae26d1c 对应的未签名安装包可从[本次构建的 Artifacts](https://codemagic.io/app/6ae160c2055898fa8b01b4e5/build/6ae16e3e206ce93970c6b5a1)下载。手机侧载、续签、权限与附近双机迁移仍待实际验收；云端构建成功不代表这些验收已通过。

[安装与续签](docs/complete-ios/INSTALL.md) · [备份格式](docs/complete-ios/BACKUP.md)
