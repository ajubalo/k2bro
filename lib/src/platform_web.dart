/// Web platform stubs.
/// Provides no-op or minimal stub implementations for all desktop-only APIs
/// so the app compiles and runs on web without crashing.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart'
    show PlatformWebViewControllerCreationParams;

Future<void> initPlatform() async {}

// ---- dart:io stubs ----

class _StderrSink {
  void writeln(Object? object) => debugPrint('[stderr] $object');
  void write(Object? object) =>
      debugPrint('[stderr] ${object?.toString() ?? ''}');
}

// ignore: non_constant_identifier_names
final _StderrSink stderr = _StderrSink();

class File {
  final String path;
  File(this.path);
  Future<bool> exists() async => false;
  Future<String> readAsString() async => '';
  Future<File> writeAsString(String contents, {dynamic mode}) async => this;
  Directory get parent {
    final idx = path.lastIndexOf('/');
    return Directory(idx < 0 ? '' : path.substring(0, idx));
  }
}

class Directory {
  final String path;
  Directory(this.path);
}

Future<Directory> getApplicationDocumentsDirectory() async => Directory('');

// ignore: non_constant_identifier_names
class InternetAddress {
  static final InternetAddress anyIPv4 = InternetAddress._();
  InternetAddress._();
}

class HttpStatus {
  static const int ok = 200;
  static const int notFound = 404;
  static const int badRequest = 400;
}

class ContentType {
  final String primaryType;
  final String subType;
  static final ContentType json = ContentType('application', 'json');
  static final ContentType html = ContentType('text', 'html');
  ContentType(this.primaryType, this.subType);
  @override
  String toString() => '$primaryType/$subType';
}

class _HttpResponseStub {
  int statusCode = 200;
  final _HttpHeadersStub headers = _HttpHeadersStub();
  void write(Object? obj) {}
  Future<void> close() async {}
}

class _HttpHeadersStub {
  ContentType? contentType;
}

class _HttpRequestHeadersStub {
  String? value(String name) => null;
  ContentType? get contentType => null;
}

class HttpRequest {
  final String method = 'GET';
  final Uri uri;
  final _HttpResponseStub response = _HttpResponseStub();
  final _HttpRequestHeadersStub headers = _HttpRequestHeadersStub();
  HttpRequest([Uri? u]) : uri = u ?? Uri();
  Stream<List<int>> asBroadcastStream() => Stream.empty();
}

class HttpServer {
  static Future<HttpServer> bind(dynamic address, int port) async =>
      HttpServer._();
  HttpServer._();
  StreamSubscription<HttpRequest> listen(
    void Function(HttpRequest) handler, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<HttpRequest>.empty().listen(handler);
  Future<void> close({bool force = false}) async {}
}

class _HttpClientHeadersStub {
  ContentType? contentType;
  void set(String name, Object value) {}
  void add(String name, Object value) {}
}

class HttpClientResponse {
  int statusCode = 200;
  Stream<String> transform(dynamic decoder) => Stream.value('{}');
  Future<String> join([String separator = '']) async => '{}';
  Future<T?> drain<T>([T? futureValue]) async => futureValue;
}

class HttpClientRequest {
  final _HttpClientHeadersStub headers = _HttpClientHeadersStub();
  void write(Object? obj) {}
  Future<HttpClientResponse> close() async => HttpClientResponse();
}

class HttpClient {
  Duration? connectionTimeout;
  Future<HttpClientRequest> postUrl(Uri url) async => HttpClientRequest();
  Future<HttpClientRequest> getUrl(Uri url) async => HttpClientRequest();
  Future<HttpClientRequest> headUrl(Uri url) async => HttpClientRequest();
  void close({bool force = false}) {}
}

// ---- dart:io Process stubs ----

class ProcessResult {
  final int exitCode;
  final Object stdout;
  final Object stderr;
  ProcessResult(this.exitCode, this.stdout, this.stderr);
}

class Process {
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
  }) async =>
      ProcessResult(1, '', 'Process not available on web');
}

// ---- media_kit stubs ----

class _PlayerStreams {
  Stream<Duration> get position => Stream.value(Duration.zero);
  Stream<Duration> get duration => Stream.value(Duration.zero);
  Stream<String> get error => Stream<String>.empty();
}

class _PlayerState {
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
}

class Player {
  final _PlayerStreams stream = _PlayerStreams();
  final _PlayerState state = _PlayerState();
  Future<void> open(dynamic media, {bool? play}) async {}
  Future<void> seek(Duration position) async {}
  Future<void> play() async {}
  Future<void> pause() async {}
  Future<void> stop() async {}
  Future<void> dispose() async {}
}

class Media {
  final String uri;
  Media(this.uri);
}

class MediaKit {
  static void ensureInitialized() {}
}

class VideoController {
  // ignore: avoid_unused_constructor_parameters
  VideoController(Player player);
}

class Video extends StatelessWidget {
  // ignore: avoid_unused_constructor_parameters
  final VideoController controller;
  final Widget Function(BuildContext)? controls;
  const Video({super.key, required this.controller, this.controls});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Video not available on web',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ),
    );
  }
}

// ---- webview_flutter_wkwebview stub ----
// Must extend PlatformWebViewControllerCreationParams so that the
// type-check in `WebViewController.fromPlatformCreationParams(params)`
// passes at compile time even though the call is inside `if (!kIsWeb)`.

class WebKitWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  final bool allowsInlineMediaPlayback;
  const WebKitWebViewControllerCreationParams({
    this.allowsInlineMediaPlayback = false,
  }) : super();
}
