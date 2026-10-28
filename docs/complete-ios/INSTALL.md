# 拾刻 iOS 构建与免费侧载

本项目不保存 Apple 密码、签名证书或手机个人数据。2026-10-28 已完成云端 macOS 原生编译，并产出约 10.64 MB 的未签名 IPA；签名安装及手机验收尚未完成。

本次安装包对应源码提交 `ae26d1c`。登录已连接的 Codemagic 个人账号后，打开[构建结果](https://codemagic.io/app/6ae160c2055898fa8b01b4e5/build/6ae16e3e206ce93970c6b5a1)，在 Artifacts 中下载 `shike-unsigned.ipa`。该包需先签名，不能直接点开安装。自动下载到 Windows 的操作尚未成功，不能将其标为已完成本地验包。图标候选稿尚未接入此安装包。

1. 源码上传至用户指定的 SgRpg/shike，按用户确认保持公开。上传采用 `tools/ios_delivery.py source` 白名单导出，环境、备份和私人素材排除。
2. 在 Codemagic 登录并选择该仓库，使用根目录 codemagic.yaml 的 ios-unsigned 工作流，手动开始。仅使用个人免费额度；额度不足时停止，禁止自动开启付费。构建预计最长 30 分钟，但计费以服务实际显示为准。
3. 下载 shike-unsigned.ipa。需要私人照片时，在签名前运行 `python tools/ios_delivery.py assets --ipa 原包.ipa --manifest 私人素材/manifest.json --output 新包.ipa`。未提供照片时不必注入。
4. 按 AltStore 官方 Windows 指南安装 AltServer、官方 iTunes/iCloud；由用户自行登录 Apple 账号并启用手机开发者模式。USB 连接后安装 AltStore，再导入本项目 IPA。
5. 保留相同 Apple 账号和应用标识，使用覆盖安装或刷新。不要删除旧 App 来升级，以免丢失沙盒数据。升级前先导出备份。
6. 免费签名通常七天到期，保持 AltServer 运行并同 Wi-Fi 或 USB 连接进行刷新。具体限制以 AltStore 及 Apple 当前提示为准。

必须在单台 iPhone 逐项检查：首次安装、重启、第二次覆盖安装、一次续签、草稿及已完成日记仍保留。没有真机结果前不得勾选完成。

官方说明：[Codemagic](https://docs.codemagic.io/billing/pricing/)、[AltStore Windows](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)、[续签](https://faq.altstore.io/altstore-classic/your-altstore)。
