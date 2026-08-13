# 漫匣（comic-webp）

漫匣是一款使用 Flutter 和 Material 3 构建的离线手机漫画管理器，面向以 WebP 页面为主的漫画压缩包和漫画文件夹。漫画导入后会自动复制到应用本地书库、整理页面顺序、识别章节，并生成可重复使用的封面缩略图。

## 已实现功能

- **导入漫画压缩包**：支持 ZIP、CBZ，自动解压并整理其中的 WebP 页面。
- **导入漫画文件夹**：递归扫描文件夹中的 WebP 文件，并根据子文件夹自动分章。
- **自然排序**：按照漫画常见的数字编号排序，例如 `2.webp` 会排在 `10.webp` 前面。
- **自动分章**：根据压缩包目录或文件夹层级识别章节，正文页面会优先排列。
- **连续阅读**：页面上下连续拼接，适合长条漫画和滚动阅读。
- **左右翻页**：支持向左翻页或向右翻页，可在阅读器中切换阅读方向。
- **阅读进度**：自动保存每本漫画的当前阅读页，下次打开可以继续阅读。
- **书签**：在阅读器中给页面添加或取消书签，也可以从书签列表快速跳转。
- **章节列表**：在阅读器中查看章节和页数，快速定位到指定章节。
- **书库文件夹**：创建、重命名和删除文件夹，将漫画移动到不同文件夹中管理。删除文件夹不会删除漫画。
- **隐私保护**：批量隐藏漫画名称，或将部分封面模糊处理；支持随时恢复显示。
- **Hero 转场动画**：书架、文件夹和漫画详情之间使用封面/文件夹转场动画。
- **Material 3 外观**：支持浅色和深色模式，适配手机屏幕。
- **性能优化**：阅读器预加载相邻页面，限制图片缓存大小，导入时节流进度刷新，并在后台补齐旧漫画的封面缩略图。
- **本地离线**：漫画页面、书签、进度、文件夹和外观设置都保存在设备本地，不依赖网络服务。

## 支持范围

- 当前仅支持 Android `arm64-v8a` 手机。
- 漫画页面格式为 WebP；压缩包支持 ZIP 和 CBZ。
- 单个页面最大 100 MB，单本漫画导入内容最大 4 GB。
- 不支持加密压缩包，也不会导入隐藏文件、`__MACOSX` 和 `Thumbs.db` 等无关文件。

## 开发与运行

环境要求：Flutter SDK（Dart SDK `^3.12.2`）和 Android SDK。

```bash
flutter pub get
flutter run
```

运行测试：

```bash
flutter analyze
flutter test
```

## 构建 ARM64 APK

在 Windows PowerShell 中执行：

```powershell
.\build-arm64.ps1
```

生成文件：

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## 项目结构

```text
lib/
  app.dart                         Material 3 应用主题
  app_controller.dart              书库状态、导入、进度和书签
  models/                          漫画和书库文件夹数据模型
  screens/                         书架、详情页和阅读器
  services/archive_organizer.dart  ZIP/CBZ/文件夹整理
  services/thumbnail_service.dart  持久化封面缩略图
  services/library_repository.dart 本地数据存储
  widgets/comic_cover.dart         封面和隐私显示
test/                               单元、组件和视觉测试
```

## 开源状态

项目仓库：[github.com/syyyh/comic-webp](https://github.com/syyyh/comic-webp)
