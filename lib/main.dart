import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 80;
  imageCache.maximumSizeBytes = 96 * 1024 * 1024;
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final controller = AppController();
  await controller.initialize();
  runApp(PanellyApp(controller: controller));
}
