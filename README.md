# 拾刻

把此刻轻轻拾起。一个只在本机保存记录的温馨日记 App，当前开发 iOS 有彩蛋版本。

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
