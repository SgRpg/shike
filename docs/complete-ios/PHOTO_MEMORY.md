# 照片素材与图片内存优化

2026-10-29，用户已授权接入 `complete/cards.dart`、`editor.dart`、`reading.dart`、`gallery.dart` 和 `complete_main.dart`。页面复用新增 `optimized_images.dart`，在解码前按显示尺寸选择像素数并保持宽高比；单张解码长边不超过2048。默认入口的图片缓存预算为不超过48MiB和100项；该值不是整个App的总内存上限。

新相册导入使用长边不超过2048、质量88的设置。系统相册原件和已有日记附件不改写。大幅放大时清晰度受2048像素预算限制。界面布局、色调、图标和间距保留。

用户提供57张私人照片，原图合计约215.9MB。Windows本地展示素材采用WebP、长边2048、质量82、保持比例、方向校正和sRGB色彩转换，总计约9.4MB，减少95.65%。原ZIP保留。缩略图及对照文件用于本地检查，不加入安装包。

素材存放在本机被排除的 `envronment/private-assets/`，不进入公开GitHub仓库或云端构建。云端仅构建工程；下载未签名IPA后，在Windows签名前运行 `tools/ios_delivery.py assets` 注入本地素材。57张照片仅作为照片卡素材池，不增加拾影累计导入张数，也不追补此前缺图跳过的奖励。

本地检查：82项Flutter测试、3项打包工具测试通过，完整静态检查无问题。新增5项图片测试包含真实800×400测试图仅解码为80×40的验证。实际iPhone总内存峰值仍需profile模式测量。

原文件通过直接逐字节比较保护，本阶段只修改上述5个授权文件。完整方案阶段开始时的其他原文件仍保留。文件验证采用CRC32、长度、结构与引用关系检查。

参考：[Flutter图片内存](https://api.flutter.dev/flutter/widgets/Image-class.html)、[Flutter图片缓存](https://api.flutter.dev/flutter/painting/ImageCache/maximumSizeBytes.html)、[WebP](https://developers.google.com/speed/webp/)。
