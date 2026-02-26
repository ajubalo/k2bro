/// Desktop platform implementation.
/// Exports all desktop-only APIs and provides [initPlatform].
library;

export 'dart:io'
    show
        File,
        Directory,
        IOSink,
        stderr,
        HttpServer,
        HttpRequest,
        HttpResponse,
        HttpHeaders,
        HttpStatus,
        ContentType,
        InternetAddress,
        HttpClient,
        HttpClientRequest,
        HttpClientResponse,
        Process,
        ProcessResult;

export 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart'
    show WebKitWebViewControllerCreationParams;

export 'package:media_kit/media_kit.dart' show Player, Media, MediaKit;
export 'package:media_kit_video/media_kit_video.dart' show VideoController, Video;
export 'package:path_provider/path_provider.dart'
    show getApplicationDocumentsDirectory;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

Future<void> initPlatform() async {
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final screenWidth = primaryDisplay.size.width;
  final screenHeight = primaryDisplay.size.height;
  final windowWidth = screenWidth * 0.9;

  final windowOptions = WindowOptions(
    size: Size(windowWidth, screenHeight),
    minimumSize: const Size(800, 600),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setPosition(const Offset(0, 0));
    await windowManager.setSize(Size(windowWidth, screenHeight));
    await windowManager.show();
    await windowManager.focus();
  });
}
