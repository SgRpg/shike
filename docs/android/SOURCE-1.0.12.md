# 安卓源码快照 1.0.12

本次同时保存完整版与公开简版的 Dart 业务代码、历次本地版本目录、Android Kotlin 宿主、依赖锁定文件、现有测试源文件、应用图标及公共文案素材。私人照片素材和签名密钥不包含在快照中。

## 工程入口

| 工程 | 用途 | 当前运行入口 |
| --- | --- | --- |
| `shike_android` | 完整业务，包括彩蛋与卡包 | `lib/github_main.dart` |
| `shike_android_plain` | 公开简版，无彩蛋与卡包 | `lib/github_main.dart` |

`github_main.dart` 显式委托 `lib/release_1_0_12/delivery_entry.dart`。为保留历史，原 `main.dart` 与此前入口未覆盖，运行和编译时请指定此入口。

```sh
cd shike_android
flutter pub get
flutter run -t lib/github_main.dart --dart-define=SHIKE_APP_VERSION=1.0.12
```

简版换用 `shike_android_plain` 目录。环境为 Flutter 3.47.8、Dart 3.13.7、JDK 17、Android SDK 36、Build Tools 36.0.0。Gradle 与 Kotlin 版本由工程文件固定。

## 发布签名

公开 APK 由本地保管的原签名密钥生成，密钥与密码不公开。

自行构建时可使用 Debug 运行；如需 Release 签名，复制 `android/key.properties.example` 为被忽略的 `android/key.properties`，填入自己的密钥信息。没有该文件时不加载私有签名配置。

```sh
flutter build apk --release -t lib/github_main.dart --target-platform android-arm,android-arm64 --dart-define=SHIKE_APP_VERSION=1.0.12
```

自行签名的 APK 与仓库发布包签名不同，不能直接覆盖原发布包。日记迁移请使用 App 内导出和导入备份。

## 私人素材

公开源码中保留了照片卡规则、素材加载与去重逻辑，移除了 `pubspec.yaml` 的私人素材资源声明。缺少素材时按现有规则跳过照片奖励，不影响日记业务。

需要在自己的本地工程加入素材时，使用 `assets/private/manifest.json` 和 `assets/private/photos/`，并在 `pubspec.yaml` 中恢复对应资源声明。整个 `assets/private/` 目录已被忽略，请不要强制加入 Git。

## 版本与回退

本次完整代码可通过发布标签 `android-1.0.12` 找回。后续功能更新通过新的 Git 提交与标签保存，历史记录不重写。

`SOURCE-1.0.12.json` 记录来源路径、长度及 CRC32，并列出导出时的配置调整。业务 Dart 和 Kotlin 按原文件保存；导出副本仅调整版本元信息、私人资源声明及本地签名加载位置，新增公开入口与忽略规则。

本次没有重新编译、运行功能测试或操作手机。测试文件作为源码保留，不表示本轮已经执行通过。
