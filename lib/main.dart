import 'package:flutter/material.dart';

import 'loaders/ios_image_loader.dart';
import 'state/album_controller.dart';
import 'theme/app_theme.dart';
import 'ui/album_home_page.dart';

// 换平台时只替换上一行 import，类名保持 PlatformImageLoader：
// import 'loaders/windows_image_loader.dart';
// import 'loaders/ios_image_loader.dart';
// import 'loaders/android_image_loader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(LighttableApp(loader: const PlatformImageLoader()));
}

class LighttableApp extends StatefulWidget {
  final PlatformImageLoader loader;

  const LighttableApp({super.key, required this.loader});

  @override
  State<LighttableApp> createState() => _LighttableAppState();
}

class _LighttableAppState extends State<LighttableApp> {
  late final AlbumController _controller = AlbumController(widget.loader);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '光桌',
      debugShowCheckedModeBanner: false,
      theme: buildDeskTheme(),
      home: AlbumHomePage(controller: _controller),
    );
  }
}
