import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
// Platform-conditional: desktop APIs on macOS, stubs on web.
// ignore: uri_does_not_exist
import 'src/platform_desktop.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) 'src/platform_web.dart';
import 'src/tree.dart';
import 'src/utils.dart';

// Tag and rating constants
const List<String> kTagKeys = ['blo', 'dog', 'fro', 'bak', 'ass', 'cum'];
const List<String> kTagEmojis = ['\u{1F48B}', '\u{1F415}', '\u{1F600}', '\u{1F351}', '\u{1F3AF}', '\u{1F4A6}'];
const List<String> kRatingLabels = ['Super', 'Top', 'Ok', 'Uhm', 'Bad'];
final List<Color> kRatingColors = [Colors.red, Colors.amber, Colors.green, Colors.blue, Colors.grey];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initPlatform(); // no-op on web; window + media_kit setup on desktop
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'K2Bro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

// ============================================================
// Data model for the tree (data.json)
// ============================================================
class AppData {
  // domain -> path -> url -> info
  Map<String, Map<String, Map<String, Map<String, dynamic>>>> data = {};

  AppData();

  factory AppData.fromJson(Map<String, dynamic> json) {
    final appData = AppData();
    json.forEach((domain, paths) {
      if (paths is Map<String, dynamic>) {
        appData.data[domain] = {};
        paths.forEach((path, urls) {
          if (urls is Map<String, dynamic>) {
            appData.data[domain]![path] = {};
            urls.forEach((url, info) {
              if (info is Map<String, dynamic>) {
                // Deep copy to ensure tags list is mutable
                final copy = <String, dynamic>{};
                info.forEach((k, v) {
                  if (v is List) {
                    copy[k] = v.map((e) => e is Map ? Map<String, dynamic>.from(e) : e).toList();
                  } else {
                    copy[k] = v;
                  }
                });
                appData.data[domain]![path]![url] = copy;
              } else {
                appData.data[domain]![path]![url] = {};
              }
            });
          }
        });
      }
    });
    return appData;
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    data.forEach((domain, paths) {
      final pathMap = <String, dynamic>{};
      paths.forEach((path, urls) {
        final urlMap = <String, dynamic>{};
        urls.forEach((url, info) {
          urlMap[url] = info;
        });
        pathMap[path] = urlMap;
      });
      result[domain] = pathMap;
    });
    return result;
  }

  /// Strip trailing '/' from a path (unless the path is just '/').
  static String normalizePath(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  void addSite(String domain, String path) {
    data.putIfAbsent(domain, () => {});
    final p = normalizePath(path);
    if (p.isNotEmpty && p != '/') {
      data[domain]!.putIfAbsent(p, () => {});
    }
  }

  void addLink(String domain, String path, String url) {
    final p = normalizePath(path);
    data.putIfAbsent(domain, () => {});
    data[domain]!.putIfAbsent(p, () => {});
    data[domain]![p]!.putIfAbsent(url, () => {});
  }

  void removeLink(String domain, String path, String url) {
    data[domain]?[normalizePath(path)]?.remove(url);
  }

  void removePath(String domain, String path) {
    data[domain]?.remove(normalizePath(path));
  }

  void removeDomain(String domain) {
    data.remove(domain);
  }

  List<String> get domains => data.keys.toList()..sort();

  List<String> pathsFor(String domain) => (data[domain]?.keys.toList() ?? [])..sort();

  List<String> linksFor(String domain, String path) =>
      data[domain]?[path]?.keys.where((k) => k != '__meta__').toList() ?? [];

  List<String> visibleLinksFor(String domain, String path) {
    final entries = data[domain]?[path]?.entries
        .where((e) => e.key != '__meta__' && e.value['hidden'] != true && e.value['rating'] != 5)
        .toList() ?? [];
    // Sort: rated first (ascending by rating), then unrated; alphabetical within same rating
    entries.sort((a, b) {
      final ra = a.value['rating'] as int?;
      final rb = b.value['rating'] as int?;
      if (ra != null && rb != null) {
        final cmp = ra.compareTo(rb);
        if (cmp != 0) return cmp;
        return a.key.compareTo(b.key);
      }
      if (ra != null) return -1;
      if (rb != null) return 1;
      return a.key.compareTo(b.key);
    });
    return entries.map((e) => e.key).toList();
  }

  bool isHidden(String domain, String path, String url) =>
      data[domain]?[path]?[url]?['hidden'] == true;

  void setHidden(String domain, String path, String url, bool hidden) {
    data[domain]?[path]?[url]?['hidden'] = hidden;
  }

  Map<String, dynamic>? linkInfo(String domain, String path, String url) =>
      data[domain]?[path]?[url];

  void addTag(String domain, String path, String url, int frame, String tag) {
    final info = data[domain]?[path]?[url];
    if (info == null) return;
    final tags = info.putIfAbsent('tags', () => <dynamic>[]) as List<dynamic>;
    // Don't duplicate
    final exists = tags.any((t) => t is Map && t['frame'] == frame && t['tag'] == tag);
    if (!exists) {
      tags.add({'frame': frame, 'tag': tag});
    }
  }

  void removeTag(String domain, String path, String url, int frame, String tag) {
    final info = data[domain]?[path]?[url];
    if (info == null) return;
    final tags = info['tags'];
    if (tags is List) {
      tags.removeWhere((t) => t is Map && t['frame'] == frame && t['tag'] == tag);
    }
  }

  List<Map<String, dynamic>> getTags(String domain, String path, String url) {
    final info = data[domain]?[path]?[url];
    if (info == null) return [];
    final tags = info['tags'];
    if (tags is List) {
      return tags.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  void setRating(String domain, String path, String url, int rating) {
    final info = data[domain]?[path]?[url];
    if (info == null) return;
    info['rating'] = rating;
  }

  int? getRating(String domain, String path, String url) {
    return data[domain]?[path]?[url]?['rating'] as int?;
  }

  void setSourcePage(String domain, String path, String url, String sourcePage) {
    final info = data[domain]?[path]?[url];
    if (info == null) return;
    info['source_page'] = sourcePage;
  }

  String? getSourcePage(String domain, String path, String url) {
    return data[domain]?[path]?[url]?['source_page'] as String?;
  }

  void setVr(String domain, String path, String url, bool vr) {
    final info = data[domain]?[path]?[url];
    if (info == null) return;
    info['vr'] = vr;
  }

  bool getVr(String domain, String path, String url) {
    return data[domain]?[path]?[url]?['vr'] == true;
  }

  void setFileSize(String domain, String path, String url, int bytes) {
    final info = data[domain]?[path]?[url];
    if (info == null) return;
    info['file_size'] = bytes;
  }

  int? getFileSize(String domain, String path, String url) {
    return data[domain]?[path]?[url]?['file_size'] as int?;
  }

  // Path-level rating (stored in __meta__ key)
  void setPathRating(String domain, String path, int rating) {
    final pathMap = data[domain]?[path];
    if (pathMap == null) return;
    pathMap.putIfAbsent('__meta__', () => <String, dynamic>{});
    (pathMap['__meta__'] as Map<String, dynamic>)['rating'] = rating;
  }

  int? getPathRating(String domain, String path) {
    return data[domain]?[path]?['__meta__']?['rating'] as int?;
  }

  /// Returns visible links for a domain/path filtered by a specific rating.
  List<String> visibleLinksWithRating(String domain, String path, int rating) {
    return data[domain]?[path]?.entries
        .where((e) => e.key != '__meta__' && e.value['hidden'] != true
            && e.value['rating'] == rating)
        .map((e) => e.key)
        .toList() ?? [];
  }

  /// Returns visible links that have no rating.
  List<String> visibleUnratedLinks(String domain, String path) {
    return data[domain]?[path]?.entries
        .where((e) => e.key != '__meta__' && e.value['hidden'] != true
            && e.value['rating'] == null)
        .map((e) => e.key)
        .toList() ?? [];
  }

  /// Returns paths under a domain that have a specific path rating.
  List<String> pathsWithRating(String domain, int rating) {
    return (data[domain]?.entries
        .where((e) => getPathRating(domain, e.key) == rating)
        .map((e) => e.key)
        .toList() ?? [])..sort();
  }

  /// Returns paths under a domain that have no path rating.
  List<String> unratedPaths(String domain) {
    return (data[domain]?.entries
        .where((e) => getPathRating(domain, e.key) == null)
        .map((e) => e.key)
        .toList() ?? [])..sort();
  }
}

// ============================================================
// Recent video entry
// ============================================================
class RecentVideo {
  final String k2sUrl; // original k2s.cc URL
  String downloadUrl; // resolved download URL
  final String title; // filename part
  double position; // last position in seconds
  double maxPosition; // furthest position reached in seconds
  int totalFrames; // total frames from preview
  double? _probedDuration; // cached ffprobe duration in seconds
  DateTime lastPlayed;
  final DateTime createdAt; // when first added to recents

  RecentVideo({
    required this.k2sUrl,
    required this.downloadUrl,
    required this.title,
    this.position = 0,
    this.maxPosition = 0,
    this.totalFrames = 0,
    DateTime? lastPlayed,
    DateTime? createdAt,
  }) : lastPlayed = lastPlayed ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  factory RecentVideo.fromJson(Map<String, dynamic> json) {
    return RecentVideo(
      k2sUrl: json['k2sUrl'] ?? '',
      downloadUrl: json['downloadUrl'] ?? '',
      title: json['title'] ?? '',
      position: (json['position'] ?? 0).toDouble(),
      maxPosition: (json['maxPosition'] ?? json['position'] ?? 0).toDouble(),
      totalFrames: json['totalFrames'] ?? 0,
      lastPlayed: DateTime.tryParse(json['lastPlayed'] ?? '') ?? DateTime.now(),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.tryParse(json['lastPlayed'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'k2sUrl': k2sUrl,
        'downloadUrl': downloadUrl,
        'title': title,
        'position': position,
        'maxPosition': maxPosition,
        'totalFrames': totalFrames,
        'lastPlayed': lastPlayed.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  /// Total duration in seconds estimated from totalFrames (each frame = 10s)
  double get durationSeconds => totalFrames * 10.0;

  /// Percentage of video watched (based on maxPosition)
  int get watchedPercent {
    if (durationSeconds <= 0) return 0;
    return (maxPosition / durationSeconds * 100).round().clamp(0, 100);
  }

  bool get isExpired => DateTime.now().difference(lastPlayed).inHours >= 24;
}

// ============================================================
// Main Page with split panes
// ============================================================
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // Vertical split ratio (left/right)
  double _verticalSplit = 0.5;

  // Horizontal split ratios
  double _leftHorizontalSplit = 0.5;
  double _rightHorizontalSplit = 0.6;

  // Data model
  AppData _appData = AppData();
  String _dataFilePath = '';

  // Config
  Map<String, String> _sites = {};
  List<String> _extractPrefixes = [];

  // Browser state
  late final WebViewController _browserController;
  final TextEditingController _addressController = TextEditingController();
  String _currentUrl = 'https://www.google.com';
  String? _selectedSite;

  // Video player state
  final List<bool> _dropdownSortByRating = [false, false]; // per-player: false = sort by %, true = sort by rating
  int _selectedPlayer = 0; // which player's radio is selected (0 or 1)
  late final List<Player> _players;
  late final List<VideoController> _videoControllers;
  final List<String?> _playerK2sUrls = [null, null]; // k2s URL currently playing
  final List<String?> _playerDownloadUrls = [null, null]; // resolved download URL
  String? _currentPreviewK2sUrl; // which k2s URL the preview is showing
  int _currentPreviewTotalFrames = 0; // total frames in current preview
  final List<int> _playerTotalFrames = [0, 0]; // total frames per player
  final List<FocusNode> _playerFocusNodes = [FocusNode(), FocusNode()];
  final List<StreamSubscription?> _pendingSeeks = [null, null];
  final List<DateTime?> _playerOpenedAt = [null, null]; // when each player last opened a new video

  // Recent videos
  List<RecentVideo> _recentVideos = [];
  String _recentFilePath = '';
  String _searchFilePath = '';

  // Recents web server
  HttpServer? _recentsServer;
  bool _recentsServerActive = false;

  // Tree
  final GlobalKey<TreeViewState> _treeKey = GlobalKey<TreeViewState>();
  TreeSelection _treeSelection = const TreeSelection();
  final List<(String, List<(String, String, String)>)> _searchResults = [];

  // Info data (index.json + .env credentials from Documents folder)
  Map<String, Map<String, String>> _infoData = {};
  String _infoU = '';
  String _infoP = '';
  String _infoH = '';

  // Pick scope: remembers which node was selected when Pick was first pressed
  String? _pickScopeDomain;
  String? _pickScopePath;
  List<String>? _pickScopeGroupPaths;

  // Extract loop state
  bool _deepExtract = false;
  bool _extractLooping = false;
  int _extractLoopPage = 0;
  final TextEditingController _extractLimitController = TextEditingController(text: '0');
  WebViewController? _extractController; // offscreen controller for extract loop
  String _extractUrl = ''; // URL tracker for offscreen controller

  // K2S API
  static const _k2sApiBase = 'https://keep2share.cc/api/v2';

  // Periodic position tracker
  Timer? _positionTimer;

  @override
  void initState() {
    super.initState();

    _players = [Player(), Player()];
    _videoControllers = [
      VideoController(_players[0]),
      VideoController(_players[1]),
    ];

    _loadConfig();
    _loadData();
    _loadRecent();
    _loadSearches();
    _loadInfoData();
    _loadInfoEnv();
    _addressController.text = _currentUrl;

    // Periodically update max position and percentage
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _savePlayerPositions();
      if (mounted) setState(() {});
    });

    // Listen for player errors and playing state changes
    for (int i = 0; i < 2; i++) {
      final idx = i;
      _players[i].stream.error.listen((error) {
        stderr.writeln('[player$idx] error: $error');
        _onPlayerError(idx);
      });
      _players[i].stream.playing.listen((_) {
        if (mounted) setState(() {});
      });
    }

    if (!kIsWeb) {
      _browserController = WebViewController.fromPlatformCreationParams(
          WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true))
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              return NavigationDecision.navigate;
            },
            onPageStarted: (String url) {
              setState(() {
                _addressController.text = url;
              });
            },
            onPageFinished: (String url) {
              setState(() {
                _currentUrl = url;
                _addressController.text = url;
              });
            },
          ),
        )
        ..addJavaScriptChannel(
          'FrameClick',
          onMessageReceived: (JavaScriptMessage message) {
            final msg = message.message;
            // Recents page messages routed through FrameClick
            if (msg.startsWith('recents:')) {
              _onRecentsClick(msg.substring(8));
              return;
            }
            // Double-click: add blo tag and play video at frame
            if (msg.startsWith('dblclick:')) {
              final frame = int.tryParse(msg.substring(9));
              if (frame != null) {
                _onFrameDoubleClicked(frame);
              }
              return;
            }
            // Fallback: tag and rating messages routed through FrameClick
            if (msg.startsWith('tag:')) {
              final parts = msg.substring(4).split(':');
              if (parts.length == 2) {
                final frame = int.tryParse(parts[0]);
                final tagKey = parts[1];
                if (frame != null && kTagKeys.contains(tagKey)) {
                  _onTagClicked(frame, tagKey);
                }
              }
              return;
            }
            if (msg.startsWith('rate:')) {
              final rating = int.tryParse(msg.substring(5));
              if (rating != null && rating >= 1 && rating <= 5) {
                _onRatingClicked(rating);
              }
              return;
            }
            if (msg.startsWith('play:')) {
              final url = msg.substring(5);
              if (isK2sFileUrl(url)) {
                _currentPreviewK2sUrl = url;
                _onFrameClicked(0);
              }
              return;
            }
            final frame = int.tryParse(msg);
            if (frame != null) {
              _onFrameClicked(frame);
            }
          },
        )
        ..addJavaScriptChannel(
          'FrameRightClick',
          onMessageReceived: (JavaScriptMessage message) {
            final frame = int.tryParse(message.message);
            if (frame != null) {
              _onFrameRightClicked(frame);
            }
          },
        )
        ..addJavaScriptChannel(
          'TagClick',
          onMessageReceived: (JavaScriptMessage message) {
            stderr.writeln('[tag] TagClick received: "${message.message}"');
            // format: "frame:tagkey"
            final parts = message.message.split(':');
            if (parts.length == 2) {
              final frame = int.tryParse(parts[0]);
              final tagKey = parts[1];
              stderr.writeln('[tag] parsed frame=$frame tagKey=$tagKey valid=${frame != null && kTagKeys.contains(tagKey)}');
              if (frame != null && kTagKeys.contains(tagKey)) {
                _onTagClicked(frame, tagKey);
              }
            } else {
              stderr.writeln('[tag] unexpected format, parts=${parts.length}');
            }
          },
        )
        ..addJavaScriptChannel(
          'RatingClick',
          onMessageReceived: (JavaScriptMessage message) {
            final rating = int.tryParse(message.message);
            if (rating != null && rating >= 1 && rating <= 5) {
              _onRatingClicked(rating);
            }
          },
        )
        ..addJavaScriptChannel(
          'RecentsClick',
          onMessageReceived: (JavaScriptMessage message) {
            _onRecentsClick(message.message);
          },
        )
        ..loadRequest(Uri.parse(_currentUrl));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      globalOverlay = Overlay.of(context);
    } catch (_) {}
  }

  @override
  void reassemble() {
    super.reassemble();
    _flashTimer?.cancel();
    _flashMessage = null;
    // Clean up stale overlay entries and reset tree state
    closeAllSpriteHovers();
    _treeKey.currentState?.resetState();
    // Refresh global overlay reference
    try {
      globalOverlay = Overlay.of(context);
    } catch (_) {}
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _positionTimer?.cancel();
    for (final s in _pendingSeeks) { s?.cancel(); }
    _savePlayerPositions();
    for (final p in _players) {
      p.dispose();
    }
    for (final f in _playerFocusNodes) {
      f.dispose();
    }
    _addressController.dispose();
    _extractLimitController.dispose();
    _extractController = null;
    _recentsServer?.close();
    super.dispose();
  }

  /// Create an offscreen WebViewController for extraction. Desktop only.
  WebViewController _createExtractController() {
    assert(!kIsWeb, '_createExtractController called on web');
    final controller = WebViewController.fromPlatformCreationParams(
        WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: false))
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            _extractUrl = url;
          },
        ),
      );
    return controller;
  }

  /// The controller to use for extraction (offscreen if looping, main otherwise).
  /// Must only be called when [kIsWeb] is false.
  WebViewController get _activeExtractController {
    assert(!kIsWeb, '_activeExtractController accessed on web');
    return _extractController ?? _browserController;
  }

  /// The current URL of the active extraction controller.
  String get _activeExtractUrl => _extractController != null ? _extractUrl : _currentUrl;

  /// Load a URL in the extraction controller.
  void _loadExtractUrl(String url) {
    if (kIsWeb) return;
    String urlToLoad = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      urlToLoad = 'https://$url';
    }
    _activeExtractController.loadRequest(Uri.parse(urlToLoad));
  }

  /// Wait until _extractUrl differs from [originalUrl], polling every 500ms.
  Future<void> _waitForExtractUrlChange(String originalUrl, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_extractUrl == originalUrl) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('Extract URL did not change', timeout);
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // ============================================================
  // Config & Data loading
  // ============================================================

  Future<void> _loadConfig() async {
    try {
      final String configString = await rootBundle.loadString('config.json');
      final Map<String, dynamic> config = json.decode(configString);
      setState(() {
        _sites = Map<String, String>.from(config['sites'] ?? {});
        _extractPrefixes = List<String>.from(config['extract'] ?? []);
        if (_sites.isNotEmpty) {
          _selectedSite = _sites.keys.first;
        }
      });
    } catch (e) {
      stderr.writeln('Error loading config: $e');
    }
  }

  Future<String> _getDataFilePath() async {
    if (_dataFilePath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      _dataFilePath = '${dir.path}/k2bro_data.json';
    }
    return _dataFilePath;
  }

  Future<void> _loadData() async {
    try {
      final path = await _getDataFilePath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonData = json.decode(content) as Map<String, dynamic>;
        setState(() {
          _appData = AppData.fromJson(jsonData);
        });
      }
    } catch (e) {
      stderr.writeln('Error loading data: $e');
    }
  }

  Future<void> _saveData() async {
    try {
      final path = await _getDataFilePath();
      final file = File(path);
      final jsonString = const JsonEncoder.withIndent('  ').convert(_appData.toJson());
      await file.writeAsString(jsonString);
    } catch (e) {
      stderr.writeln('Error saving data: $e');
    }
  }

  // ============================================================
  // Recent videos persistence
  // ============================================================

  Future<String> _getRecentFilePath() async {
    if (_recentFilePath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      _recentFilePath = '${dir.path}/k2bro_recent.json';
    }
    return _recentFilePath;
  }

  Future<void> _loadRecent() async {
    try {
      final path = await _getRecentFilePath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = json.decode(content);
        final loaded = list
            .map((e) => RecentVideo.fromJson(e as Map<String, dynamic>))
            .where((v) => !v.isExpired)
            .toList();
        // Deduplicate by k2sUrl (keep latest)
        final deduped = <String, RecentVideo>{};
        for (final v in loaded) {
          final existing = deduped[v.k2sUrl];
          if (existing == null || v.lastPlayed.isAfter(existing.lastPlayed)) {
            deduped[v.k2sUrl] = v;
          }
        }
        setState(() {
          _recentVideos = deduped.values.toList();
        });
      }
    } catch (e) {
      stderr.writeln('Error loading recent: $e');
    }
  }

  Future<void> _saveRecent() async {
    try {
      // Remove expired entries
      _recentVideos.removeWhere((v) => v.isExpired);
      final path = await _getRecentFilePath();
      final file = File(path);
      final jsonString = const JsonEncoder.withIndent('  ')
          .convert(_recentVideos.map((v) => v.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
      stderr.writeln('Error saving recent: $e');
    }
  }

  // ============================================================
  // Search persistence
  // ============================================================

  Future<String> _getSearchFilePath() async {
    if (_searchFilePath.isEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      _searchFilePath = '${dir.path}/k2bro_searches.json';
    }
    return _searchFilePath;
  }

  Future<void> _loadSearches() async {
    try {
      final path = await _getSearchFilePath();
      final file = File(path);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = json.decode(content);
        setState(() {
          _searchResults.clear();
          for (final item in list) {
            final pattern = item['pattern'] as String;
            final matches = (item['matches'] as List<dynamic>)
                .map((m) => (m[0] as String, m[1] as String, m[2] as String))
                .toList();
            _searchResults.add((pattern, matches));
          }
        });
      }
    } catch (e) {
      stderr.writeln('Error loading searches: $e');
    }
  }

  Future<void> _saveSearches() async {
    try {
      final path = await _getSearchFilePath();
      final file = File(path);
      final list = _searchResults.map((s) => {
        'pattern': s.$1,
        'matches': s.$2.map((m) => [m.$1, m.$2, m.$3]).toList(),
      }).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(list);
      await file.writeAsString(jsonString);
    } catch (e) {
      stderr.writeln('Error saving searches: $e');
    }
  }

  // ============================================================
  // Info data loading (index.json + .env from Documents)
  // ============================================================

  Future<void> _loadInfoData() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/index.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonData = json.decode(content) as Map<String, dynamic>;
        final loaded = <String, Map<String, String>>{};
        jsonData.forEach((folder, sizes) {
          if (sizes is Map<String, dynamic>) {
            loaded[folder] = {};
            sizes.forEach((sizeKey, path) {
              if (path is String) {
                loaded[folder]![sizeKey] = path;
              }
            });
          }
        });
        setState(() {
          _infoData = loaded;
        });
      }
    } catch (e) {
      stderr.writeln('Error loading info data: $e');
    }
  }

  Future<void> _loadInfoEnv() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/.env');
      if (await file.exists()) {
        final content = await file.readAsString();
        for (final line in content.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx < 0) continue;
          final key = trimmed.substring(0, eqIdx).trim();
          final value = trimmed.substring(eqIdx + 1).trim();
          if (key == 'U') _infoU = value;
          else if (key == 'P') _infoP = value;
          else if (key == 'H') _infoH = value;
        }
      }
    } catch (e) {
      stderr.writeln('Error loading .env: $e');
    }
  }

  void _savePlayerPositions() {
    final toRemove = <String>[];
    for (int i = 0; i < 2; i++) {
      final k2sUrl = _playerK2sUrls[i];
      if (k2sUrl == null) continue;
      final pos = _players[i].state.position.inMilliseconds / 1000.0;
      final idx = _recentVideos.indexWhere((v) => v.k2sUrl == k2sUrl);
      if (idx >= 0) {
        _recentVideos[idx].position = pos;
        if (pos > _recentVideos[idx].maxPosition) {
          _recentVideos[idx].maxPosition = pos;
        }
        _recentVideos[idx].lastPlayed = DateTime.now();
        // Auto-remove at 90% watched
        if (_recentVideos[idx].watchedPercent >= 90) {
          toRemove.add(k2sUrl);
        }
      }
    }
    if (toRemove.isNotEmpty) {
      setState(() {
        for (final url in toRemove) {
          _recentVideos.removeWhere((v) => v.k2sUrl == url);
          for (int i = 0; i < 2; i++) {
            if (_playerK2sUrls[i] == url) {
              _playerK2sUrls[i] = null;
              _playerDownloadUrls[i] = null;
              _playerTotalFrames[i] = 0;
              _players[i].stop();
            }
          }
        }
      });
    }
    _saveRecent();
  }

  // ============================================================
  // K2S API
  // ============================================================

  Future<String?> _getK2sToken() async {
    if (kIsWeb) return null;
    final dir = await getApplicationDocumentsDirectory();
    final tokenFile = File('${dir.path}/.token');
    stderr.writeln('[k2s] checking token at: ${tokenFile.path}');
    if (await tokenFile.exists()) {
      final token = (await tokenFile.readAsString()).trim();
      if (token.isNotEmpty) {
        stderr.writeln('[k2s] found token (${token.length} chars)');
        return token;
      }
    }
    stderr.writeln('[k2s] no .token found at ${tokenFile.path}');
    return null;
  }

  Future<String?> _getDownloadUrl(String k2sUrl) async {
    if (kIsWeb) return null;
    final fileId = extractFileId(k2sUrl);
    if (fileId == null) return null;

    // Check connectivity first
    if (!await _checkConnectivity()) {
      stderr.writeln('[k2s] connectivity check failed');
      if (mounted) {
        _showFlash('Cannot connect to K2S. Check your internet connection.');
      }
      return null;
    };
    final token = await _getK2sToken();
    if (token == null) {
      if (mounted) {
        _showFlash('No token found. Run "uv run util.py link <url>" first to generate .token');
      }
      return null;
    }

    try {
      stderr.writeln('[k2s] calling getUrl with file_id=$fileId token=${token.substring(0, 8)}...');
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$_k2sApiBase/getUrl'));
      request.headers.contentType = ContentType.json;
      request.write(json.encode({'file_id': fileId, 'auth_token': token}));
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
      client.close();

      final data = json.decode(body) as Map<String, dynamic>;
      if (data['status'] == 'success') {
        return data['url'] as String;
      } else {
        stderr.writeln('[k2s] getUrl failed: $data');
        if (mounted) {
          _showFlash('getUrl failed: ${data['message'] ?? data}');
        }
        return null;
      }
    } catch (e) {
      stderr.writeln('[k2s] error: $e');
      return null;
    }
  }

  // ============================================================
  // Video playback
  // ============================================================

  String _titleFromK2sUrl(String url) {
    final id = extractFileId(url);
    if (id != null) {
      final idx = url.indexOf(id);
      final rest = url.substring(idx + id.length);
      if (rest.startsWith('/') && rest.length > 1) {
        return rest.substring(1);
      }
      return id;
    }
    return url;
  }

  Future<void> _onFrameClicked(int frame) async {
    // Tag/rating popup shown in JS near the mouse

    final k2sUrl = _currentPreviewK2sUrl;
    if (k2sUrl == null) return;

    final playerIdx = _selectedPlayer;

    // If this player is already playing the same video, just seek
    if (_playerK2sUrls[playerIdx] == k2sUrl) {
      final seekMs = frame * 10 * 1000;
      _players[playerIdx].seek(Duration(milliseconds: seekMs));
      _playerFocusNodes[playerIdx].requestFocus();
      return;
    }

    // Save current position before switching
    _savePlayerPositions();

    // Check if we already have a recent entry with the download URL
    var recent = _recentVideos.where((v) => v.k2sUrl == k2sUrl).firstOrNull;
    String? downloadUrl = recent?.downloadUrl;

    if (downloadUrl == null || downloadUrl.isEmpty) {
      // Get the download URL from the API
      downloadUrl = await _getDownloadUrl(k2sUrl);
      if (downloadUrl == null) return;
    }

    // Add or update recent entry
    final title = _titleFromK2sUrl(k2sUrl);
    final clickedPositionSec = frame * 10.0;
    if (recent != null) {
      recent.downloadUrl = downloadUrl;
      recent.lastPlayed = DateTime.now();
      recent.totalFrames = _currentPreviewTotalFrames;
    } else {
      recent = RecentVideo(
        k2sUrl: k2sUrl,
        downloadUrl: downloadUrl,
        title: title,
        totalFrames: _currentPreviewTotalFrames,
      );
      // Set initial maxPosition to the clicked frame position
      recent.maxPosition = clickedPositionSec;
      _recentVideos.add(recent);
    }
    _saveRecent();

    // Ensure link exists in tree data
    if (_findLinkLocation(k2sUrl) == null && isK2sFileUrl(k2sUrl)) {
      _appData.addSite('k2s.cc', 'file');
      _appData.addLink('k2s.cc', 'file', k2sUrl);
      _saveData();
    }

    // Promote blue to green when playing
    _promoteBlueToGreen(k2sUrl);

    setState(() {
      _playerK2sUrls[playerIdx] = k2sUrl;
      _playerDownloadUrls[playerIdx] = downloadUrl;
      _playerTotalFrames[playerIdx] = _currentPreviewTotalFrames;
    });

    _playerOpenedAt[playerIdx] = DateTime.now();
    _players[playerIdx].open(Media(downloadUrl));
    _playerFocusNodes[playerIdx].requestFocus();

    // Seek to frame position once video is loaded
    final seekMs = frame * 10 * 1000;
    _seekWhenReady(playerIdx, seekMs);
  }

  double _latestSeekPosition(RecentVideo video) {
    double seekSec = video.maxPosition;
    final location = _findLinkLocation(video.k2sUrl);
    if (location != null) {
      final (domain, path) = location;
      final tags = _appData.getTags(domain, path, video.k2sUrl);
      for (final tag in tags) {
        final frameSec = (tag['frame'] as int) * 10.0;
        if (frameSec > seekSec) seekSec = frameSec;
      }
    }
    return seekSec;
  }

  void _removeAndPlayNext(int playerIdx, String k2sUrl, {String? reason}) {
    if (!mounted) return;
    final video = _recentVideos.where((v) => v.k2sUrl == k2sUrl).firstOrNull;
    final title = video?.title ?? k2sUrl;
    if (reason != null) {
      stderr.writeln('[player$playerIdx] $reason for "$title"');
      _showFlash('$reason: $title');
    }

    // Build sorted list before removing, to find next
    final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    validRecent.sort((a, b) {
      final ra = _getRatingForK2sUrl(a.k2sUrl);
      final rb = _getRatingForK2sUrl(b.k2sUrl);
      if (ra != null && rb != null) {
        final cmp = ra.compareTo(rb);
        if (cmp != 0) return cmp;
      }
      if (ra != null && rb == null) return -1;
      if (ra == null && rb != null) return 1;
      return a.createdAt.compareTo(b.createdAt);
    });
    final currentIdx = validRecent.indexWhere((v) => v.k2sUrl == k2sUrl);

    // Remove the video
    setState(() {
      _recentVideos.removeWhere((v) => v.k2sUrl == k2sUrl);
      _playerK2sUrls[playerIdx] = null;
      _playerDownloadUrls[playerIdx] = null;
      _playerTotalFrames[playerIdx] = 0;
    });
    _players[playerIdx].stop();
    _saveRecent();

    // Move to next video in the list (at same index position, wrapping)
    final remaining = validRecent.where((v) => v.k2sUrl != k2sUrl).toList();
    if (remaining.isEmpty) return;
    final nextIdx = currentIdx >= remaining.length ? 0 : currentIdx.clamp(0, remaining.length - 1);
    final next = remaining[nextIdx];
    _switchVideo(playerIdx, next, seekPosition: _latestSeekPosition(next));
  }

  void _onPlayerError(int playerIdx) {
    final k2sUrl = _playerK2sUrls[playerIdx];
    if (k2sUrl == null) return;

    // Only remove from recents if error occurs within 1 second of opening
    // (indicates expired/dead URL). Later errors (e.g. seek on AVI) are just logged.
    final openedAt = _playerOpenedAt[playerIdx];
    if (openedAt != null && DateTime.now().difference(openedAt).inMilliseconds < 1000) {
      // Check connectivity first — don't expire if connection is bad
      _checkConnectivity().then((connected) {
        if (connected) {
          _removeAndPlayNext(playerIdx, k2sUrl, reason: 'Download expired');
        } else {
          stderr.writeln('[player$playerIdx] error for "$k2sUrl" but connectivity is down, not removing');
          if (mounted) {
            _showFlash('Playback failed — connection issue. Video kept in recents.');
          }
        }
      });
    } else {
      stderr.writeln('[player$playerIdx] non-fatal error for "$k2sUrl" (seek/playback issue, not removing)');
    }
  }

  Future<bool> _checkConnectivity() async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      final request = await client.headUrl(Uri.parse('https://keep2share.cc'));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  void _seekWhenReady(int playerIdx, int seekMs) {
    _pendingSeeks[playerIdx]?.cancel();
    _pendingSeeks[playerIdx] = _players[playerIdx].stream.duration.listen((duration) {
      if (duration.inMilliseconds > 0 && seekMs > 0) {
        _pendingSeeks[playerIdx]?.cancel();
        _pendingSeeks[playerIdx] = null;
        _players[playerIdx].seek(Duration(milliseconds: seekMs));
      }
    });
  }

  /// Promote blue (Uhm/4) rated video to green (Ok/3) when played.
  void _promoteBlueToGreen(String k2sUrl) {
    final location = _findLinkLocation(k2sUrl);
    if (location == null) return;
    final (domain, path) = location;
    final rating = _appData.getRating(domain, path, k2sUrl);
    if (rating == 4) {
      setState(() {
        _appData.setRating(domain, path, k2sUrl, 3);
      });
      _saveData();
    }
  }

  void _switchVideo(int playerIdx, RecentVideo video, {double? seekPosition}) {
    // Save current position
    _savePlayerPositions();

    // Promote blue to green when playing
    _promoteBlueToGreen(video.k2sUrl);

    setState(() {
      _playerK2sUrls[playerIdx] = video.k2sUrl;
      _playerDownloadUrls[playerIdx] = video.downloadUrl;
      _playerTotalFrames[playerIdx] = video.totalFrames;
    });

    _playerOpenedAt[playerIdx] = DateTime.now();
    _players[playerIdx].open(Media(video.downloadUrl));
    _playerFocusNodes[playerIdx].requestFocus();

    final seekMs = ((seekPosition ?? video.position) * 1000).round();
    _seekWhenReady(playerIdx, seekMs);

    video.lastPlayed = DateTime.now();
    _saveRecent();
  }

  void _goToAdjacentVideo(int playerIdx, List<RecentVideo> sortedRecent, int direction) {
    if (sortedRecent.isEmpty) return;
    _savePlayerPositions();

    final currentUrl = _playerK2sUrls[playerIdx];
    int currentIdx = sortedRecent.indexWhere((v) => v.k2sUrl == currentUrl);
    int nextIdx;
    if (currentIdx < 0) {
      nextIdx = direction > 0 ? 0 : sortedRecent.length - 1;
    } else {
      nextIdx = currentIdx + direction;
      if (nextIdx >= sortedRecent.length) nextIdx = 0;
      if (nextIdx < 0) nextIdx = sortedRecent.length - 1;
    }
    final video = sortedRecent[nextIdx];
    _switchVideo(playerIdx, video, seekPosition: _latestSeekPosition(video));
  }

  void _openPreviewForPlayer(int playerIdx) {
    final k2sUrl = _playerK2sUrls[playerIdx];
    if (k2sUrl != null) {
      _previewLink(k2sUrl);
    }
  }

  // ============================================================
  // Tagging & Rating
  // ============================================================

  Future<void> _onFrameRightClicked(int frame) async {
    // Popup shown in JS, no navigation needed
    // Also add to recents without playing
    final k2sUrl = _currentPreviewK2sUrl;
    if (k2sUrl == null) return;

    // Already in recents — nothing to do
    if (_recentVideos.any((v) => v.k2sUrl == k2sUrl)) return;

    final downloadUrl = await _getDownloadUrl(k2sUrl);
    if (downloadUrl == null) return;

    final title = _titleFromK2sUrl(k2sUrl);
    final recent = RecentVideo(
      k2sUrl: k2sUrl,
      downloadUrl: downloadUrl,
      title: title,
      totalFrames: _currentPreviewTotalFrames,
    );
    recent.maxPosition = frame * 10.0;
    setState(() { _recentVideos.add(recent); });
    _saveRecent();
    _showFlash('Added to recents: $title');
  }

  Future<void> _onFrameDoubleClicked(int frame) async {
    // Add "blo" tag at this frame
    _onTagClicked(frame, 'blo');
    // Play the video and seek to the frame
    final k2sUrl = _currentPreviewK2sUrl;
    if (k2sUrl == null) return;
    final playerIdx = _selectedPlayer;

    // If already playing same video, just seek
    if (_playerK2sUrls[playerIdx] == k2sUrl) {
      final seekMs = frame * 10 * 1000;
      _players[playerIdx].seek(Duration(milliseconds: seekMs));
      _playerFocusNodes[playerIdx].requestFocus();
      return;
    }

    // Start the video via _onFrameClicked (which uses _seekWhenReady)
    await _onFrameClicked(frame);
  }

  void _onTagClicked(int frame, String tagKey) {
    final k2sUrl = _currentPreviewK2sUrl;
    stderr.writeln('[tag] _onTagClicked frame=$frame tagKey=$tagKey k2sUrl=$k2sUrl');
    if (k2sUrl == null) {
      if (mounted) {
        _showFlash('Tag: no preview URL');
      }
      return;
    }
    final location = _findLinkLocation(k2sUrl);
    stderr.writeln('[tag] location=$location');
    if (location == null) {
      if (mounted) {
        _showFlash('Tag: link not found in data for $k2sUrl');
      }
      return;
    }
    final (domain, path) = location;
    setState(() {
      // Auto-rate green (3=Ok) if previously unrated, blue (4=Uhm), or grey (5=Bad)
      final currentRating = _appData.getRating(domain, path, k2sUrl);
      if (currentRating == null || currentRating == 4 || currentRating == 5) {
        _appData.setRating(domain, path, k2sUrl, 3);
      }
      _appData.addTag(domain, path, k2sUrl, frame, tagKey);
    });
    final tags = _appData.getTags(domain, path, k2sUrl);
    stderr.writeln('[tag] after addTag, tags=$tags totalFrames=${_playerTotalFrames}');
    if (mounted) {
      _showFlash('Tag added: $tagKey at frame $frame (${tags.length} total)');
    }
    _saveData();
  }

  void _onRatingClicked(int rating) {
    final k2sUrl = _currentPreviewK2sUrl;
    if (k2sUrl == null) return;
    final location = _findLinkLocation(k2sUrl);
    if (location == null) return;
    final (domain, path) = location;
    final targets = _rarGroupPartsFor(k2sUrl);
    setState(() {
      for (final t in targets) {
        _appData.setRating(domain, path, t, rating);
      }
    });
    _saveData();
    // Auto-pick next random link
    _pickRandomLink();
  }

  // ============================================================
  // Flash message (centered overlay, fades quickly)
  // ============================================================

  String? _flashMessage;
  Timer? _flashTimer;

  void _showFlash(String message) {
    if (!mounted) return;
    _flashTimer?.cancel();
    setState(() { _flashMessage = message; });
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() { _flashMessage = null; });
    });
  }

  // ============================================================
  // Browser & URL
  // ============================================================

  void _loadUrl(String url) {
    if (kIsWeb) return;
    _currentPreviewK2sUrl = null;
    String urlToLoad = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      urlToLoad = 'https://$url';
    }
    _browserController.loadRequest(Uri.parse(urlToLoad));
  }

  /// Returns a playable k2s URL: browser URL first, then preview, then selected tree link.
  String? get _playableK2sUrl {
    if (isK2sFileUrl(_currentUrl)) return _currentUrl;
    if (_currentPreviewK2sUrl != null && isK2sFileUrl(_currentPreviewK2sUrl!)) return _currentPreviewK2sUrl;
    if (_treeSelection.link != null && isK2sFileUrl(_treeSelection.link!)) return _treeSelection.link;
    return null;
  }

  /// Whether the current context has a playable info video.
  bool get _hasPlayableInfoVideo {
    return _treeSelection.category == 'info' && _currentPreviewK2sUrl != null;
  }

  Future<void> _playK2sUrl() async {
    final url = _playableK2sUrl;
    if (url == null) return;
    _currentPreviewK2sUrl = url;
    await _onFrameClicked(0);
  }

  void _playCurrentInfoVideo() {
    if (_currentPreviewK2sUrl == null) return;
    final folder = _treeSelection.domain;
    final name = _currentPreviewK2sUrl!.split('/').last;
    // Reverse-engineer the path from the video URL
    final urlPrefix = 'https://$_infoU:$_infoP@$_infoU.$_infoH/';
    final path = _currentPreviewK2sUrl!.startsWith(urlPrefix)
        ? _currentPreviewK2sUrl!.substring(urlPrefix.length)
        : name;
    _playInfoVideo(path, name, folder: folder);
  }

  // ============================================================
  // Info video helpers
  // ============================================================

  String _buildInfoVideoUrl(String path) {
    return 'https://$_infoU:$_infoP@$_infoU.$_infoH/$path';
  }

  /// Ensure an AppData entry exists for an info link so tagging/rating works.
  void _ensureInfoEntry(String folder, String videoUrl) {
    if (_findLinkLocation(videoUrl) == null) {
      _appData.addLink(folder, 'info', videoUrl);
      _saveData();
    }
  }

  void _showInfoPreview(String path, {String? folder}) {
    if (kIsWeb) return;
    final videoUrl = _buildInfoVideoUrl(path);
    if (folder != null) {
      _ensureInfoEntry(folder, videoUrl);
    }
    setState(() {
      _currentPreviewK2sUrl = videoUrl;
    });
    final basename = path.split('/').last;
    final escapedTitle = basename.replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8">
<style>
  body { background: #222; color: #ddd; font: 14px sans-serif; margin: 0; padding: 8px; }
  h3 { margin: 4px 0 8px; font-size: 14px; }
  video { width: 100%; max-height: 80vh; background: #000; }
</style>
</head>
<body>
<h3>$escapedTitle</h3>
<video controls autoplay>
  <source src="$videoUrl" type="video/mp4">
</video>
</body>
</html>
''';
    _browserController.loadHtmlString(html, baseUrl: 'https://$_infoU.$_infoH');
  }

  void _playInfoVideo(String path, String name, {String? folder}) {
    final videoUrl = _buildInfoVideoUrl(path);
    if (folder != null) {
      _ensureInfoEntry(folder, videoUrl);
    }
    final playerIdx = _selectedPlayer;
    _savePlayerPositions();

    setState(() {
      _playerK2sUrls[playerIdx] = videoUrl;
      _playerDownloadUrls[playerIdx] = videoUrl;
      _playerTotalFrames[playerIdx] = 0;
    });

    _playerOpenedAt[playerIdx] = DateTime.now();
    _players[playerIdx].open(Media(videoUrl));
    _playerFocusNodes[playerIdx].requestFocus();
  }

  Future<void> _downloadK2sUrl() async {
    final url = _playableK2sUrl;
    if (url == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final keyPath = '${dir.path}/id_rsa';
    final command = "echo '/mnt/data/deobro/get.sh $url' | ssh -i '$keyPath' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null onyx.n7s.co at now";
    final log = <String>[command, ''];
    _showLogPage(log);

    try {
      final result = await Process.run('/bin/bash', ['-c', command]);
      log.add('Exit code: ${result.exitCode}');
      if ((result.stdout as String).isNotEmpty) {
        log.add('');
        log.add(result.stdout as String);
      }
      if ((result.stderr as String).isNotEmpty) {
        log.add('');
        log.add(result.stderr as String);
      }
      log.add('');
      log.add(result.exitCode == 0 ? 'Download scheduled.' : 'FAILED');
      if (!mounted) return;
      _showLogPage(log);
      _showFlash(result.exitCode == 0 ? 'Download scheduled' : 'Download failed');
    } catch (e) {
      log.add('');
      log.add('Error: $e');
      if (!mounted) return;
      _showLogPage(log);
      _showFlash('Download error: $e');
    }
  }


  void _addCurrentSite() {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;

    final domain = uri.scheme == 'http' ? 'http://${uri.host}' : uri.host;
    var path = uri.path;
    if (uri.query.isNotEmpty) {
      path = '$path?${uri.query}';
    }

    _addSiteWithPath(domain, path);
  }

  void _addSiteWithPath(String domain, String path) {
    path = AppData.normalizePath(path);
    stderr.writeln('[add] domain=$domain path=$path');
    setState(() {
      _appData.addSite(domain, path);
    });
    final effectivePath = (path.isNotEmpty && path != '/') ? path : null;
    if (effectivePath != null) {
      _treeKey.currentState?.navigateToLink(domain, effectivePath, '');
    } else {
      _treeKey.currentState?.selectLink(domain, '', '');
    }
    _treeKey.currentState?.clearPickScope();
    stderr.writeln('[add] domains=${_appData.domains} pathsFor($domain)=${_appData.pathsFor(domain)}');
    _saveData();
  }

  void _addCurrentSiteWithDialog() {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;

    final domain = uri.scheme == 'http' ? 'http://${uri.host}' : uri.host;
    var defaultPath = uri.path;
    if (uri.query.isNotEmpty) {
      defaultPath = '$defaultPath?${uri.query}';
    }

    final controller = TextEditingController(text: defaultPath);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add path to $domain'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '/path'),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    ).then((path) {
      if (path != null && path.isNotEmpty) {
        _addSiteWithPath(domain, path);
      }
    });
  }

  Future<(Map<String, bool>, Map<String, int>)> _checkFilesAvailability(List<String> fileIds) async {
    final result = <String, bool>{};
    final sizes = <String, int>{};
    if (kIsWeb || fileIds.isEmpty) return (result, sizes);

    final token = await _getK2sToken();
    const batchSize = 100;
    for (int i = 0; i < fileIds.length; i += batchSize) {
      final batch = fileIds.sublist(i, (i + batchSize).clamp(0, fileIds.length));
      try {
        final payload = <String, dynamic>{'ids': batch, 'extended_info': false};
        if (token != null) {
          payload['auth_token'] = token;
        }

        final client = HttpClient();
        final request = await client.postUrl(Uri.parse('$_k2sApiBase/getFilesInfo'));
        request.headers.contentType = ContentType.json;
        request.write(json.encode(payload));
        final response = await request.close();
        final body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
        client.close();

        final data = json.decode(body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          final files = data['files'] as List<dynamic>? ?? [];
          for (final f in files) {
            if (f is Map<String, dynamic>) {
              final id = f['id'] as String?;
              final rawAvail = f['is_available'];
              final available = rawAvail is bool ? rawAvail : rawAvail == 1 || rawAvail == '1' || rawAvail == 'true';
              if (id != null) {
                result[id] = available;
                final rawSize = f['size'];
                final size = rawSize is int ? rawSize : rawSize is double ? rawSize.toInt() : rawSize is String ? int.tryParse(rawSize) : null;
                if (size != null) sizes[id] = size;
              }
            }
          }
        } else {
          stderr.writeln('[k2s] getFilesInfo batch ${i ~/ batchSize + 1} failed: $data');
        }
      } catch (e) {
        stderr.writeln('[k2s] getFilesInfo batch ${i ~/ batchSize + 1} error: $e');
      }
      stderr.writeln('[k2s] getFilesInfo batch ${i ~/ batchSize + 1}: ${result.length} checked so far');
    }
    return (result, sizes);
  }


  (String, String)? _findLinkLocation(String url) {
    for (final domain in _appData.data.keys) {
      for (final path in _appData.data[domain]!.keys) {
        if (_appData.data[domain]![path]!.containsKey(url)) {
          return (domain, path);
        }
      }
    }
    return null;
  }

  /// Return all sibling RAR part URLs if url belongs to a multi-part group, or [url] if standalone.
  List<String> _rarGroupPartsFor(String url) {
    final loc = _findLinkLocation(url);
    if (loc == null) return [url];
    final (domain, path) = loc;
    final links = _appData.visibleLinksFor(domain, path);
    final grouped = groupRarParts(links);
    for (final item in grouped) {
      if (item is RarGroup && item.parts.contains(url)) {
        return item.parts;
      }
    }
    return [url];
  }

  /// Build a small sprite thumbnail widget for a k2s URL at a given position.
  Widget? _spriteThumbnail(String k2sUrl, double positionSec, {double? width, double? height, double size = 28}) {
    final fileId = extractFileId(k2sUrl);
    if (fileId == null) return null;
    const gridSize = 5;
    const framesPerImage = gridSize * gridSize;
    final frame = positionSec ~/ 10;
    final spriteIdx = frame ~/ framesPerImage;
    final posInSprite = frame % framesPerImage;
    final row = posInSprite ~/ gridSize;
    final col = posInSprite % gridSize;
    final spriteUrl = 'https://static-cache.k2s.cc/sprite/$fileId/${spriteIdx.toString().padLeft(2, '0')}.jpeg';
    final w = width ?? size;
    final h = height ?? size;
    // Render sprite at gridSize× container size, offset to the right cell, clip
    return SizedBox(
      width: w,
      height: h,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: w * gridSize,
          maxHeight: h * gridSize,
          alignment: Alignment.topLeft,
          child: Transform.translate(
            offset: Offset(-col * w, -row * h),
            child: Image.network(
              spriteUrl,
              width: w * gridSize,
              height: h * gridSize,
              fit: BoxFit.fill,
              errorBuilder: (_, __, ___) => SizedBox(width: w, height: h),
            ),
          ),
        ),
      ),
    );
  }

  /// Fetch a page via HTTP and extract all k2s file links from its HTML.
  Future<List<String>> _extractK2sLinksFromPage(String pageUrl) async {
    if (kIsWeb) return [];
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(pageUrl));
      request.headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36');
      final response = await request.close();
      if (response.statusCode != 200) {
        stderr.writeln('[deep] HTTP ${response.statusCode} for $pageUrl');
        client.close();
        return [];
      }
      final body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
      client.close();
      // Find all http(s)://k2s.cc/file/... or keep2share.cc/file/... links in the HTML
      final pattern = RegExp(r'https?://(k2s\.cc|keep2share\.cc)/file/[^\s"<>]+');
      return pattern.allMatches(body).map((m) => m.group(0)!).toSet().toList();
    } catch (e) {
      stderr.writeln('[deep] Failed to fetch $pageUrl: $e');
      return [];
    }
  }

  /// Deep extraction: find all same-site page links from the browser, then
  /// fetch each via HTTP and collect k2s links from their HTML.
  Future<(List<String>, Map<String, String>)> _deepExtractLinks(String origin) async {
    // Step 1: extract all same-origin <a> hrefs from the current page
    // Matches both relative URLs (resolved by browser) and absolute URLs with same origin
    final jsCode = '''
      (function() {
        var pageHost = new URL(${json.encode(origin)}).hostname.replace(/^www\\./, '');
        var seen = {};
        var results = [];
        var links = document.getElementsByTagName('a');
        for (var i = 0; i < links.length; i++) {
          var href = links[i].href;
          if (!href) continue;
          try {
            var linkHost = new URL(href).hostname.replace(/^www\\./, '');
            if (linkHost === pageHost && !seen[href]) {
              seen[href] = true;
              results.push(href);
            }
          } catch(e) {}
        }
        return JSON.stringify(results);
      })()
    ''';
    final result = await _activeExtractController.runJavaScriptReturningResult(jsCode);
    String resultString = result.toString();
    if (resultString.startsWith('"') && resultString.endsWith('"')) {
      resultString = resultString.substring(1, resultString.length - 1);
      resultString = resultString.replaceAll(r'\"', '"');
    }
    final List<dynamic> pageUrls = json.decode(resultString);
    stderr.writeln('[deep] Found ${pageUrls.length} same-site pages');

    // Step 2: fetch each page and extract k2s links
    final allK2sLinks = <String>[];
    final linkToSourcePage = <String, String>{};
    for (final pageUrl in pageUrls) {
      final pageUrlStr = pageUrl.toString();
      final links = await _extractK2sLinksFromPage(pageUrlStr);
      if (links.isNotEmpty) {
        stderr.writeln('[deep] $pageUrlStr: ${links.length} k2s links');
        for (final link in links) {
          allK2sLinks.add(link);
          linkToSourcePage[link] = pageUrlStr;
        }
      }
    }
    stderr.writeln('[deep] Total: ${allK2sLinks.length} k2s links from ${pageUrls.length} pages');
    return (allK2sLinks, linkToSourcePage);
  }

  /// Extract links from the current browser page using JavaScript.
  Future<List<String>> _extractLinksFromBrowser() async {
    if (kIsWeb) return [];
    final prefixesJson = json.encode(_extractPrefixes);
    final jsCode = '''
      (function() {
        var prefixes = $prefixesJson;
        var seen = {};
        var matchingHrefs = [];
        function addUrl(url) {
          if (!seen[url]) {
            seen[url] = true;
            matchingHrefs.push(url);
          }
        }
        // Scan <a> href attributes
        var links = document.getElementsByTagName('a');
        for (var i = 0; i < links.length; i++) {
          var href = links[i].href;
          if (href) {
            for (var j = 0; j < prefixes.length; j++) {
              if (href.startsWith(prefixes[j])) {
                addUrl(href);
                break;
              }
            }
          }
        }
        // Scan page HTML for k2s links (catches links in text, href, etc.)
        var text = document.body ? document.body.innerHTML : '';
        var re = /https?:\\/\\/k2s\\.cc\\/file\\/[^\\s"'<>]+/g;
        var m;
        while ((m = re.exec(text)) !== null) {
          addUrl(m[0]);
        }
        return JSON.stringify(matchingHrefs);
      })()
    ''';
    final result = await _activeExtractController.runJavaScriptReturningResult(jsCode);
    String resultString = result.toString();
    if (resultString.startsWith('"') && resultString.endsWith('"')) {
      resultString = resultString.substring(1, resultString.length - 1);
    }
    resultString = resultString.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
    final List<dynamic> hrefs = json.decode(resultString);
    return hrefs.map((e) => e.toString()).toList();
  }

  /// Extract the filename portion from a k2s URL (after /file/<id>/).
  String _k2sLinkName(String url) {
    final match = RegExp(r'https?://(k2s\.cc|keep2share\.cc)/file/').firstMatch(url);
    if (match == null) return url;
    final rest = url.substring(match.end);
    final slashIdx = rest.indexOf('/');
    if (slashIdx < 0) return '';
    return rest.substring(slashIdx + 1);
  }

  /// Merge link info (tags, rating, source_page) from one link into another.
  void _mergeLinkInfo(String domain, String path, String fromUrl, String toUrl) {
    final fromInfo = _appData.linkInfo(domain, path, fromUrl);
    final toInfo = _appData.linkInfo(domain, path, toUrl);
    if (fromInfo == null || toInfo == null) return;

    // Merge tags
    final fromTags = _appData.getTags(domain, path, fromUrl);
    for (final tag in fromTags) {
      _appData.addTag(domain, path, toUrl, tag['frame'] as int, tag['tag'] as String);
    }

    // Keep the better (lower number) rating
    final fromRating = _appData.getRating(domain, path, fromUrl);
    final toRating = _appData.getRating(domain, path, toUrl);
    if (fromRating != null && (toRating == null || fromRating < toRating)) {
      _appData.setRating(domain, path, toUrl, fromRating);
    }

    // Keep source_page if target doesn't have one
    final fromSource = _appData.getSourcePage(domain, path, fromUrl);
    final toSource = _appData.getSourcePage(domain, path, toUrl);
    if (fromSource != null && toSource == null) {
      _appData.setSourcePage(domain, path, toUrl, fromSource);
    }
  }

  /// Add extracted links to the tree, checking availability.
  /// Deduplicates by file ID (keeps the URL with the longest filename).
  /// On re-extraction, preserves tags and ratings, removes unavailable and duplicates.
  /// [linkToSourcePage] maps k2s URLs to their source page (for forum extraction).
  Future<void> _addExtractedLinks(String domain, String path, List<String> hrefStrings, {Map<String, String>? linkToSourcePage}) async {
    stderr.writeln('[extract] Starting extraction: ${hrefStrings.length} raw links for $domain $path');
    final urlToId = <String, String>{};
    for (final href in hrefStrings) {
      final id = extractFileId(href);
      if (id != null) {
        urlToId[href] = id;
      } else {
        stderr.writeln('[extract] SKIP no file ID: $href');
      }
    }
    stderr.writeln('[extract] ${urlToId.length} links with valid file IDs');

    // Deduplicate: for each file ID, keep the URL with the longest name
    final bestUrlForId = <String, String>{};
    for (final entry in urlToId.entries) {
      final id = entry.value;
      final url = entry.key;
      final existing = bestUrlForId[id];
      if (existing == null || _k2sLinkName(url).length > _k2sLinkName(existing).length) {
        if (existing != null) {
          stderr.writeln('[extract] DEDUP $id: keep "${_k2sLinkName(url)}" over "${_k2sLinkName(existing)}"');
        }
        bestUrlForId[id] = url;
      }
    }
    final dedupedUrls = bestUrlForId.values.toSet();
    stderr.writeln('[extract] ${dedupedUrls.length} unique file IDs after dedup');

    stderr.writeln('[extract] Checking availability for ${bestUrlForId.keys.length} IDs...');
    final (availability, fileSizes) = await _checkFilesAvailability(bestUrlForId.keys.toList());
    final availableCount = availability.values.where((v) => v).length;
    final unavailableCount = availability.values.where((v) => !v).length;
    stderr.writeln('[extract] Availability: $availableCount available, $unavailableCount unavailable');

    setState(() {
      _appData.addSite(domain, path);
      // Ensure path exists even if addSite skips '/'
      _appData.data.putIfAbsent(domain, () => {});
      _appData.data[domain]!.putIfAbsent(path, () => {});
      int added = 0;
      int removed = 0;
      int deduped = 0;

      // Also deduplicate existing links in the tree
      final existingLinks = _appData.linksFor(domain, path);
      stderr.writeln('[extract] ${existingLinks.length} existing links in tree for this path');
      final existingById = <String, List<String>>{};
      for (final link in existingLinks) {
        final id = extractFileId(link);
        if (id != null) {
          existingById.putIfAbsent(id, () => []).add(link);
        }
      }

      // Remove existing duplicates (keep the one with longest name)
      for (final entry in existingById.entries) {
        if (entry.value.length <= 1) continue;
        entry.value.sort((a, b) => _k2sLinkName(b).length.compareTo(_k2sLinkName(a).length));
        final keeper = entry.value.first;
        for (int i = 1; i < entry.value.length; i++) {
          stderr.writeln('[extract] MERGE existing dup ${entry.key}: remove "${_k2sLinkName(entry.value[i])}", keep "${_k2sLinkName(keeper)}"');
          _mergeLinkInfo(domain, path, entry.value[i], keeper);
          _appData.removeLink(domain, path, entry.value[i]);
          _recentVideos.removeWhere((v) => v.k2sUrl == entry.value[i]);
          deduped++;
        }
      }

      // Process newly extracted links
      for (final href in dedupedUrls) {
        final id = urlToId[href]!;
        final isAvailable = availability[id] ?? false;
        final currentLinks = _appData.linksFor(domain, path);
        final alreadyExists = currentLinks.contains(href);
        // Check if another URL for the same ID already exists
        final existingForId = currentLinks.where((l) => extractFileId(l) == id).toList();

        if (isAvailable) {
          if (existingForId.isNotEmpty && !alreadyExists) {
            // Same file ID exists under a different URL — merge and replace if new name is longer
            final existing = existingForId.first;
            if (_k2sLinkName(href).length > _k2sLinkName(existing).length) {
              stderr.writeln('[extract] ADD+REPLACE $id: "${_k2sLinkName(href)}" replaces "${_k2sLinkName(existing)}"');
              _appData.addLink(domain, path, href);
              _mergeLinkInfo(domain, path, existing, href);
              _appData.removeLink(domain, path, existing);
              _recentVideos.removeWhere((v) => v.k2sUrl == existing);
              added++;
            } else {
              stderr.writeln('[extract] SKIP $id: existing "${_k2sLinkName(existing)}" already has longer/equal name than "${_k2sLinkName(href)}"');
            }
          } else if (!alreadyExists) {
            stderr.writeln('[extract] ADD $id: "${_k2sLinkName(href)}"');
            _appData.addLink(domain, path, href);
            added++;
          } else {
            stderr.writeln('[extract] SKIP $id: already exists "${_k2sLinkName(href)}"');
          }
          // Store source_page and file size if available
          final targetUrl = _appData.linksFor(domain, path).where((l) => extractFileId(l) == id).firstOrNull ?? href;
          if (linkToSourcePage != null && linkToSourcePage.containsKey(href)) {
            _appData.setSourcePage(domain, path, targetUrl, linkToSourcePage[href]!);
          }
          if (fileSizes.containsKey(id)) {
            _appData.setFileSize(domain, path, targetUrl, fileSizes[id]!);
          }
        } else {
          stderr.writeln('[extract] UNAVAILABLE $id: "${_k2sLinkName(href)}"');
          // Remove unavailable (not hidden) links
          for (final existing in existingForId) {
            if (!_appData.isHidden(domain, path, existing)) {
              stderr.writeln('[extract] REMOVE unavailable: "${_k2sLinkName(existing)}"');
              _appData.removeLink(domain, path, existing);
              _recentVideos.removeWhere((v) => v.k2sUrl == existing);
              removed++;
            } else {
              stderr.writeln('[extract] KEEP hidden unavailable: "${_k2sLinkName(existing)}"');
            }
          }
        }
      }

      stderr.writeln('[extract] SUMMARY: $added added, $removed removed, $deduped duplicates merged (${hrefStrings.length} found)');

      if (mounted) {
        final parts = <String>[];
        if (added > 0) parts.add('$added added');
        if (removed > 0) parts.add('$removed removed');
        if (deduped > 0) parts.add('$deduped duplicates merged');
        final summary = parts.isEmpty ? 'No changes' : parts.join(', ');
        _showFlash('$summary (${hrefStrings.length} found)');
      }
      // Navigate tree to show extracted links
      _treeKey.currentState?.navigateToLink(domain, path, '');
      _treeKey.currentState?.clearPickScope();
    });
    _saveData();
  }

  /// Compute the next page URL for pagination after extraction.
  /// Handles `start=XXX` (+30) and `pageXXX` (+1) patterns.
  /// Always matches the LAST occurrence in the URL.
  String? _nextPageUrl(String url) {
    // Match last start=XXX (query parameter)
    final startPattern = RegExp(r'([\?&]start=)(\d+)');
    final startMatches = startPattern.allMatches(url).toList();
    if (startMatches.isNotEmpty) {
      final lastMatch = startMatches.last;
      final num = int.parse(lastMatch.group(2)!);
      final before = url.substring(0, lastMatch.start);
      final after = url.substring(lastMatch.end);
      return '$before${lastMatch.group(1)}${num + 30}$after';
    }
    // Match last pageXXX in URL
    final pagePattern = RegExp(r'(page)(\d+)');
    final pageMatches = pagePattern.allMatches(url).toList();
    if (pageMatches.isNotEmpty) {
      final lastMatch = pageMatches.last;
      final num = int.parse(lastMatch.group(2)!);
      final before = url.substring(0, lastMatch.start);
      final after = url.substring(lastMatch.end);
      return '$before${lastMatch.group(1)}${num + 1}$after';
    }
    // Match /<number>/ at the end (e.g., .../page/3/ -> .../page/4/)
    final slashNumSlash = RegExp(r'/(\d+)/$');
    final slashMatch = slashNumSlash.firstMatch(url);
    if (slashMatch != null) {
      final num = int.parse(slashMatch.group(1)!);
      return '${url.substring(0, slashMatch.start)}/${num + 1}/';
    }
    // Match trailing number in the path only (e.g., .../something3 -> .../something4)
    // Strip query string so we don't match numeric query parameter values
    final queryIndex = url.indexOf('?');
    final pathPart = queryIndex >= 0 ? url.substring(0, queryIndex) : url;
    final queryPart = queryIndex >= 0 ? url.substring(queryIndex) : '';
    final trailingNum = RegExp(r'(\d+)$');
    final trailMatch = trailingNum.firstMatch(pathPart);
    if (trailMatch != null) {
      final num = int.parse(trailMatch.group(1)!);
      return '${pathPart.substring(0, trailMatch.start)}${num + 1}$queryPart';
    }
    return null;
  }

  /// Extract the current page number from a URL.
  int _currentPageNumber(String url) {
    final startPattern = RegExp(r'[\?&]start=(\d+)');
    final startMatches = startPattern.allMatches(url).toList();
    if (startMatches.isNotEmpty) {
      return int.parse(startMatches.last.group(1)!) ~/ 30 + 1;
    }
    final pagePattern = RegExp(r'page(\d+)');
    final pageMatches = pagePattern.allMatches(url).toList();
    if (pageMatches.isNotEmpty) {
      return int.parse(pageMatches.last.group(1)!);
    }
    final slashNumSlash = RegExp(r'/(\d+)/$');
    final slashMatch = slashNumSlash.firstMatch(url);
    if (slashMatch != null) {
      return int.parse(slashMatch.group(1)!);
    }
    final qIdx = url.indexOf('?');
    final pathOnly = qIdx >= 0 ? url.substring(0, qIdx) : url;
    final trailingNum = RegExp(r'(\d+)$');
    final trailMatch = trailingNum.firstMatch(pathOnly);
    if (trailMatch != null) {
      return int.parse(trailMatch.group(1)!);
    }
    return 1;
  }

  /// Right-click extract: start/stop auto-extract loop through pages.
  Future<void> _startExtractLoop() async {
    if (kIsWeb) return;
    if (_extractLooping) {
      setState(() { _extractLooping = false; });
      return;
    }
    final maxPage = int.tryParse(_extractLimitController.text) ?? 0;

    // Create offscreen controller and load the current browser URL
    _extractController = _createExtractController();
    _extractUrl = '';
    _extractController!.loadRequest(Uri.parse(_currentUrl));
    try {
      await _waitForExtractUrlChange('', const Duration(seconds: 30));
    } catch (_) {
      stderr.writeln('[extract-loop] Timeout loading initial page in offscreen');
      _extractController = null;
      return;
    }
    await Future.delayed(const Duration(seconds: 1));

    setState(() { _extractLooping = true; });
    int emptyStreak = 0;
    while (_extractLooping) {
      final url = _extractUrl;
      setState(() { _extractLoopPage = _currentPageNumber(url); });
      stderr.writeln('[extract-loop] Page $_extractLoopPage: $url');

      int found = 0;
      try {
        found = await _extractLinks();
      } catch (e) {
        stderr.writeln('[extract-loop] Error: $e');
      }
      if (!_extractLooping) break;

      // Track empty pages
      if (found == 0) {
        emptyStreak++;
        stderr.writeln('[extract-loop] Empty page ($emptyStreak/3)');
        if (emptyStreak >= 3) {
          stderr.writeln('[extract-loop] 3 consecutive empty pages, stopping');
          _showFlash('Stopped: 3 empty pages');
          break;
        }
      } else {
        emptyStreak = 0;
      }

      // _extractLinks already navigated to the next page. Wait for it to load.
      final nextUrl = _nextPageUrl(url);
      if (nextUrl == null) {
        stderr.writeln('[extract-loop] No next page, stopping loop');
        break;
      }

      // Wait until _extractUrl changes (offscreen page finished loading)
      try {
        await _waitForExtractUrlChange(url, const Duration(seconds: 30));
      } catch (_) {
        stderr.writeln('[extract-loop] Timeout waiting for page load');
        break;
      }
      if (!_extractLooping) break;

      // Check if next page number exceeds the limit (0 = unlimited)
      if (maxPage > 0) {
        final nextPageNum = _currentPageNumber(_extractUrl);
        if (nextPageNum > maxPage) {
          stderr.writeln('[extract-loop] Next page $nextPageNum > limit $maxPage, stopping');
          _showFlash('Stopped: reached page $maxPage');
          break;
        }
      }

      // Let the page render before extracting
      await Future.delayed(const Duration(seconds: 1));
    }
    _extractController = null;
    _extractUrl = '';
    setState(() {
      _extractLooping = false;
      _extractLoopPage = 0;
    });
  }

  /// Wait until _currentUrl differs from [originalUrl], polling every 500ms.
  Future<void> _waitForUrlChange(String originalUrl, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (_currentUrl == originalUrl) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('URL did not change', timeout);
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Check if a URL contains a page number pattern.
  bool _hasPageNumber(String url) => _nextPageUrl(url) != null;

  /// Extract links from the current page. Returns the number of raw links found.
  /// Uses offscreen controller when _extractController is set (loop mode).
  Future<int> _extractLinks() async {
    if (kIsWeb) return 0;
    try {
      var uri = Uri.tryParse(_activeExtractUrl);
      if (uri == null) return 0;

      var domain = uri.scheme == 'http' ? 'http://${uri.host}' : uri.host;
      var path = uri.path;
      if (uri.query.isNotEmpty) {
        path = '$path?${uri.query}';
      }
      path = AppData.normalizePath(path);

      // If the current page is numbered and this page's path already has links, navigate to next and wait.
      // Always check the URL's own path (not the selected path) so we don't skip unextracted pages.
      if (_hasPageNumber(_activeExtractUrl) && _appData.linksFor(domain, path).isNotEmpty) {
        final nextUrl = _nextPageUrl(_activeExtractUrl);
        if (nextUrl != null) {
          stderr.writeln('[extract] Path already has links, navigating to next: $nextUrl');
          final oldUrl = _activeExtractUrl;
          _loadExtractUrl(nextUrl);
          if (_extractController != null) {
            await _waitForExtractUrlChange(oldUrl, const Duration(seconds: 30));
          } else {
            await _waitForUrlChange(oldUrl, const Duration(seconds: 30));
          }
          await Future.delayed(const Duration(seconds: 1));
          // Re-parse from the loaded URL
          uri = Uri.tryParse(_activeExtractUrl);
          if (uri == null) return 0;
          domain = uri.scheme == 'http' ? 'http://${uri.host}' : uri.host;
          path = uri.path;
          if (uri.query.isNotEmpty) {
            path = '$path?${uri.query}';
          }
          path = AppData.normalizePath(path);
        }
      }

      // Keep mode: if path starts with /tags/ or /xfsearch/, extract content page links
      final lowerPath = uri.path.toLowerCase();
      if (lowerPath.startsWith('/tags/') || lowerPath.startsWith('/xfsearch/')) {
        final origin = '${uri.scheme}://${uri.host}';
        final extractUrl = _activeExtractUrl;
        int found = 0;
        try {
          found = await _extractKeepLinks(origin, domain, path);
        } catch (e) {
          stderr.writeln('[keep] Error in keep extraction: $e');
        }
        final nextUrl = _nextPageUrl(extractUrl);
        stderr.writeln('[keep] URL: $extractUrl, next URL: $nextUrl');
        if (nextUrl != null) {
          _loadExtractUrl(nextUrl);
        }
        return found;
      }

      // Forum mode: if path contains /viewforum.php (case-insensitive), follow topic links
      if (uri.path.toLowerCase().contains('/viewforum.php')) {
        final extractUrl = _activeExtractUrl;
        int found = 0;
        try {
          found = await _extractForumLinks(domain, path, uri);
        } catch (e) {
          stderr.writeln('Error in forum extraction: $e');
        }
        // Auto-navigate to next page (always, even if nothing found or error)
        final nextUrl = _nextPageUrl(extractUrl);
        stderr.writeln('[extract] Forum URL: $extractUrl, next URL: $nextUrl');
        if (nextUrl != null) {
          _loadExtractUrl(nextUrl);
        }
        return found;
      }

      // Save page HTML for debugging
      try {
        final html = await _activeExtractController.runJavaScriptReturningResult('document.documentElement.outerHTML');
        String htmlStr = html.toString();
        if (htmlStr.startsWith('"') && htmlStr.endsWith('"')) {
          htmlStr = htmlStr.substring(1, htmlStr.length - 1);
        }
        htmlStr = htmlStr.replaceAll(r'\"', '"').replaceAll(r'\n', '\n').replaceAll(r'\\', '\\');
        final dataPath = await _getDataFilePath();
        final extractPath = '${File(dataPath).parent.path}/extract.html';
        await File(extractPath).writeAsString(htmlStr);
        stderr.writeln('[extract] Saved page HTML to $extractPath');
      } catch (e) {
        stderr.writeln('[extract] Failed to save HTML: $e');
      }

      // Standard extraction: scan current page for k2s links
      // For paginated URLs, always use the URL's own path so each page gets its own tree node.
      // For non-paginated URLs, use the selected path if one is selected in the tree.
      // Also create '/' as an empty path so prefix grouping makes it the parent.
      final hasPage = _hasPageNumber(_activeExtractUrl);
      final useSelectedPath = !hasPage && _treeSelection.path != null && _treeSelection.domain == domain;
      final extractUrl = _activeExtractUrl;
      int found = 0;
      try {
        // Always extract k2s links from the current page first
        final hrefStrings = await _extractLinksFromBrowser();
        final linkToSourcePage = {for (final href in hrefStrings) href: extractUrl};
        // Group links by their target path: selected path or current URL path
        final currentPagePath = useSelectedPath ? _treeSelection.path! : path;
        final linksByPath = <String, List<String>>{currentPagePath: List.from(hrefStrings)};
        final allLinkToSourcePage = Map<String, String>.from(linkToSourcePage);
        if (_deepExtract) {
          // Deep: also follow all same-site links and extract k2s links from each
          // All deep links are stored under the parent page's path (not each source page's path)
          final origin = '${uri.scheme}://${uri.host}';
          final (deepLinks, deepSourcePages) = await _deepExtractLinks(origin);
          for (final link in deepLinks) {
            if (!allLinkToSourcePage.containsKey(link)) {
              linksByPath.putIfAbsent(currentPagePath, () => []).add(link);
            }
            allLinkToSourcePage.putIfAbsent(link, () => deepSourcePages[link] ?? extractUrl);
          }
        }
        // Ensure domain exists
        if (!useSelectedPath) {
          setState(() {
            _appData.data.putIfAbsent(domain, () => {});
          });
        }
        // Add links grouped by their target path
        for (final entry in linksByPath.entries) {
          final targetPath = entry.key;
          final links = entry.value;
          if (links.isEmpty) continue;
          found += links.length;
          stderr.writeln('[extract] Adding ${links.length} links to $domain path=$targetPath');
          await _addExtractedLinks(domain, targetPath, links, linkToSourcePage: allLinkToSourcePage);
          stderr.writeln('[extract] After add: ${_appData.linksFor(domain, targetPath).length} links in tree for $domain $targetPath');
        }
      } catch (e) {
        stderr.writeln('Error extracting links: $e');
      }

      // Auto-navigate to next page (always, even if nothing found or error)
      final nextUrl = _nextPageUrl(extractUrl);
      stderr.writeln('[extract] Current URL: $extractUrl, next URL: $nextUrl');
      if (nextUrl != null) {
        _loadExtractUrl(nextUrl);
      }
      return found;
    } catch (e) {
      stderr.writeln('Error in extract: $e');
      return 0;
    }
  }

  /// Show a log page in the browser with live-updating messages.
  /// Fetch a source page and display all its external images as a preview.
  /// Fetch source page, extract images and links, render custom preview, scroll to the k2s link.
  Future<void> _showSourcePage(String sourcePageUrl, String k2sUrl) async {
    if (kIsWeb) return;
    stderr.writeln('[preview] Fetching source page: $sourcePageUrl for $k2sUrl');
    final fileId = extractFileId(k2sUrl) ?? '';
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(sourcePageUrl));
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
      client.close();

      // Extract images
      final imgPattern = RegExp(r'''(?:src|data-src)=["']([^"']+\.(?:jpg|jpeg|png|gif|webp)[^"']*)["']''', caseSensitive: false);
      final imgUrls = <String>{};
      for (final match in imgPattern.allMatches(body)) {
        var imgUrl = match.group(1)!;
        if (imgUrl.startsWith('//')) imgUrl = 'https:$imgUrl';
        else if (imgUrl.startsWith('/')) {
          final uri = Uri.parse(sourcePageUrl);
          imgUrl = '${uri.scheme}://${uri.host}$imgUrl';
        }
        imgUrls.add(imgUrl);
      }

      // Extract k2s links
      final linkPattern = RegExp(r'https?://k2s\.cc/file/[^\s"<>]+', caseSensitive: false);
      final k2sLinks = <String>{};
      for (final match in linkPattern.allMatches(body)) {
        k2sLinks.add(match.group(0)!);
      }

      stderr.writeln('[preview] Found ${imgUrls.length} images, ${k2sLinks.length} k2s links');

      // Build HTML with images and links
      final imgTags = imgUrls.map((u) =>
        '<img src="$u" style="width:100%;display:none;margin:0 auto 8px auto;">'
      ).join('\n');

      final linkTags = k2sLinks.map((l) {
        final id = extractFileId(l) ?? '';
        var name = linkLabel(l).replaceAll('&', '&amp;').replaceAll('<', '&lt;');
        final loc = _findLinkLocation(l);
        if (loc != null) {
          final sz = _appData.getFileSize(loc.$1, loc.$2, l);
          if (sz != null) name = '${formatFileSize(sz)} $name';
        }
        final isTarget = id == fileId;
        return '<div class="k2s-link${isTarget ? ' target' : ''}" ${isTarget ? 'id="target-link"' : ''} data-url="${l.replaceAll('"', '&quot;')}">'
            '<a href="$l" style="color:#4fc3f7;font:13px sans-serif;text-decoration:none;">$name</a></div>';
      }).join('\n');

      final fallbackTitle = linkLabel(k2sUrl).replaceAll("'", "\\'").replaceAll('&', '&amp;').replaceAll('<', '&lt;');

      final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body{margin:0;padding:8px;background:#111;color:#ccc;}
::-webkit-scrollbar{width:10px;}
::-webkit-scrollbar-track{background:#222;}
::-webkit-scrollbar-thumb{background:#666;border-radius:5px;}
::-webkit-scrollbar-thumb:hover{background:#888;}
#speedbar{background:#000;padding:6px 12px;display:flex;gap:8px;align-items:center;position:fixed;top:0;left:0;right:0;z-index:100;}
#speedbar #filename{color:#ccc;font:11px sans-serif;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
#content{padding-top:40px;}
.k2s-link{padding:4px 8px;margin:2px 0;border-radius:4px;}
.k2s-link.target{background:#f44336;outline:2px solid #fff;}
.k2s-link a{display:block;}
</style></head>
<body>
<div id="speedbar">
  <span id="filename">$fallbackTitle</span>
</div>
<div id="content">
$imgTags
$linkTags
</div>
<script>
// Filter images by size
document.querySelectorAll('img').forEach(function(img) {
  img.onload = function() {
    if (img.naturalWidth > 200 && img.naturalHeight > 200) {
      img.style.display = 'block';
    } else {
      img.remove();
    }
  };
  img.onerror = function() { img.remove(); };
  img.addEventListener('click', function() {
    if (window.FrameClick) FrameClick.postMessage('0');
  });
});
// Scroll to target link
var target = document.getElementById('target-link');
if (target) {
  setTimeout(function() {
    target.scrollIntoView({behavior: 'smooth', block: 'center'});
  }, 500);
}
// Click on link to play video
document.querySelectorAll('.k2s-link').forEach(function(div) {
  div.addEventListener('click', function(e) {
    e.preventDefault();
    var url = div.getAttribute('data-url');
    if (window.FrameClick && url) FrameClick.postMessage('play:' + url);
  });
});
</script>
</body>
</html>
''';
      _browserController.loadHtmlString(html, baseUrl: sourcePageUrl);
    } catch (e) {
      stderr.writeln('[preview] Error fetching source page: $e');
      _loadUrl(k2sUrl);
    }
  }

  void _showLogPage(List<String> logLines) {
    if (kIsWeb) return;
    final escaped = logLines.map((l) =>
        l.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')).join('<br>');
    final html = '''
<!DOCTYPE html><html><head><meta charset="utf-8"><style>
body{margin:0;padding:12px;background:#111;color:#0f0;font:13px monospace;white-space:pre-wrap;}
</style></head>
<body>$escaped</body>
<script>window.scrollTo(0, document.body.scrollHeight);</script>
</html>''';
    _browserController.loadHtmlString(html, baseUrl: 'https://static-cache.k2s.cc');
  }

  /// Keep extraction: find <origin>/<number>-*.html links, fetch each,
  /// POST to reveal hidden k2s links, add them to the tree.
  Future<int> _extractKeepLinks(String origin, String domain, String path) async {
    if (kIsWeb) return 0;
    // Step 1: find content page links from the current browser page
    // Matches both www. and non-www. variants of the origin
    final jsCode = '''
      (function() {
        var origin = ${json.encode(origin)};
        var pageHost = new URL(origin).hostname.replace(/^www\\./, '');
        var seen = {};
        var results = [];
        var container = document.getElementById('midside');
        if (!container) container = document;
        var links = container.getElementsByTagName('a');
        for (var i = 0; i < links.length; i++) {
          var href = links[i].href;
          if (!href) continue;
          try {
            var linkHost = new URL(href).hostname.replace(/^www\\./, '');
            if (linkHost === pageHost && /\\/\\d+-[^/]*\\.html/.test(href) && !seen[href]) {
              seen[href] = true;
              results.push(href);
            }
          } catch(e) {}
        }
        return JSON.stringify(results);
      })()
    ''';
    final result = await _activeExtractController.runJavaScriptReturningResult(jsCode);
    String resultString = result.toString();
    if (resultString.startsWith('"') && resultString.endsWith('"')) {
      resultString = resultString.substring(1, resultString.length - 1);
      resultString = resultString.replaceAll(r'\"', '"');
    }
    final List<dynamic> contentUrls = json.decode(resultString);
    stderr.writeln('[keep] Found ${contentUrls.length} content pages');

    // Step 2: fetch each content page, find button with data-id/data-hash,
    // POST to show.php to reveal hidden links, collect k2s links
    final allK2sLinks = <String>[];
    final linkToSourcePage = <String, String>{};
    final k2sPattern = RegExp(r'https?://(k2s\.cc|keep2share\.cc)/file/[^\s"<>]+');

    for (final pageUrl in contentUrls) {
      final pageUrlStr = pageUrl.toString();
      stderr.writeln(pageUrlStr);
      try {
        final client = HttpClient();
        final pageUri = Uri.parse(pageUrlStr);
        final request = await client.getUrl(pageUri);
        final response = await request.close();
        final body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();

        // Find button with data-id and data-hash attributes (either order)
        String? dataId, dataHash;
        final m1 = RegExp(r'data-id="(\d+)"[^>]*data-hash="([^"]+)"').firstMatch(body);
        if (m1 != null) {
          dataId = m1.group(1)!;
          dataHash = m1.group(2)!;
        } else {
          final m2 = RegExp(r'data-hash="([^"]+)"[^>]*data-id="(\d+)"').firstMatch(body);
          if (m2 != null) {
            dataHash = m2.group(1)!;
            dataId = m2.group(2)!;
          }
        }

        // First, look for k2s links directly in the page body
        var links = k2sPattern.allMatches(body).map((m) => m.group(0)!).toSet().toList();

        // If no direct links found, try the data-id/data-hash button POST method
        if (links.isEmpty && dataId != null && dataHash != null) {
          final postUri = Uri.parse('${pageUri.scheme}://${pageUri.host}/engine/mods/click_hide/show.php');
          final postReq = await client.postUrl(postUri);
          postReq.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
          postReq.write('id=$dataId&hash=$dataHash&div=1');
          final postResp = await postReq.close();
          final postBody = await postResp.transform(const Utf8Decoder(allowMalformed: true)).join();
          links = k2sPattern.allMatches(postBody).map((m) => m.group(0)!).toSet().toList();
        }
        for (final link in links) {
          stderr.writeln(link);
          allK2sLinks.add(link);
          linkToSourcePage[link] = pageUrlStr;
        }
        client.close();
      } catch (e) {
        stderr.writeln('[keep]   error: $e');
      }
    }

    // Step 3: add collected links to the tree
    if (allK2sLinks.isNotEmpty) {
      await _addExtractedLinks(domain, path, allK2sLinks, linkToSourcePage: linkToSourcePage);
    }
    return allK2sLinks.length;
  }

  /// Forum extraction: find /viewtopic.php links, fetch each, extract k2s links.
  Future<int> _extractForumLinks(String domain, String path, Uri forumUri) async {
    if (kIsWeb) return 0;
    // Step 1: extract topic links from the current page BEFORE replacing it with log
    final jsCode = '''
      (function() {
        var links = document.getElementsByTagName('a');
        var topics = [];
        for (var i = 0; i < links.length; i++) {
          var href = links[i].href;
          if (href && href.toLowerCase().indexOf('/viewtopic.php') >= 0) {
            topics.push(href);
          }
        }
        return JSON.stringify([...new Set(topics)]);
      })()
    ''';
    final result = await _activeExtractController.runJavaScriptReturningResult(jsCode);
    String resultString = result.toString();
    if (resultString.startsWith('"') && resultString.endsWith('"')) {
      resultString = resultString.substring(1, resultString.length - 1);
    }
    resultString = resultString.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');
    final List<dynamic> topicUrls = json.decode(resultString);

    // Show log page only when not using offscreen controller (user can browse)
    final log = <String>[];
    void addLog(String msg) {
      log.add(msg);
      stderr.writeln('[forum] $msg');
      if (_extractController == null) {
        _showLogPage(log);
      }
    }

    addLog('Forum extraction: $forumUri');
    addLog('Found ${topicUrls.length} topic links.');

    if (topicUrls.isEmpty) {
      addLog('No topics to process.');
      return 0;
    }

    // Step 2: fetch each topic page and extract k2s links
    final allK2sLinks = <String>[];
    final linkToSourcePage = <String, String>{};

    for (int i = 0; i < topicUrls.length; i++) {
      final url = topicUrls[i].toString();
      addLog('[${i + 1}/${topicUrls.length}] Fetching: $url');
      final k2sLinks = await _extractK2sLinksFromPage(url);
      addLog('[${i + 1}/${topicUrls.length}]   → ${k2sLinks.length} links found');
      for (final link in k2sLinks) {
        if (!allK2sLinks.contains(link)) {
          allK2sLinks.add(link);
        }
        linkToSourcePage[link] = url;
      }
    }

    addLog('');
    addLog('Total unique k2s links: ${allK2sLinks.length}');
    addLog('Checking availability...');

    // Step 3: add to tree with source_page info
    await _addExtractedLinks(domain, path, allK2sLinks, linkToSourcePage: linkToSourcePage);

    addLog('Done.');
    return allK2sLinks.length;
  }

  void _removeSelected() {
    final sel = _treeSelection;
    if (sel.link != null && sel.path != null && sel.domain != null) {
      setState(() {
        _appData.removeLink(sel.domain!, sel.path!, sel.link!);
      });
      _saveData();
    } else if (sel.path != null && sel.domain != null) {
      _showConfirmDialog('Remove path "${sel.path}" and all its links?', () {
        setState(() {
          _appData.removePath(sel.domain!, sel.path!);
        });
        _saveData();
      });
    } else if (sel.domain != null) {
      _showConfirmDialog('Remove website "${sel.domain}" and all its content?', () {
        setState(() {
          _appData.removeDomain(sel.domain!);
        });
        _saveData();
      });
    }
  }

  void _removeBySubstring() {
    if (_treeSelection.domain == null) return;
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove links by name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Substring to match in link name'),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Find'),
          ),
        ],
      ),
    ).then((substring) {
      if (substring == null || substring.isEmpty) return;
      final sub = substring.toLowerCase();
      final allLinks = <(String, String, String)>[];
      final sel = _treeSelection;
      final domain = sel.domain!;
      if (sel.path != null) {
        for (final link in _appData.linksFor(domain, sel.path!)) {
          allLinks.add((domain, sel.path!, link));
        }
      } else if (sel.groupPaths != null) {
        for (final path in sel.groupPaths!) {
          for (final link in _appData.linksFor(domain, path)) {
            allLinks.add((domain, path, link));
          }
        }
      } else {
        for (final path in _appData.pathsFor(domain)) {
          for (final link in _appData.linksFor(domain, path)) {
            allLinks.add((domain, path, link));
          }
        }
      }
      final matching = allLinks.where((t) => _k2sLinkName(t.$3).toLowerCase().contains(sub)).toList();
      if (matching.isEmpty) {
        _showFlash('No links found matching "$substring"');
        return;
      }
      _showConfirmDialog(
        'Found ${matching.length} links with "$substring" out of ${allLinks.length} links. Remove them?',
        () {
          setState(() {
            for (final (d, p, l) in matching) {
              _appData.removeLink(d, p, l);
              _recentVideos.removeWhere((v) => v.k2sUrl == l);
            }
          });
          _saveData();
          _showFlash('Removed ${matching.length} links');
        },
      );
    });
  }

  void _showConfirmDialog(String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Removal'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Pick random link
  // ============================================================

  /// Clear pick scope when user manually selects a tree node.
  void _clearPickScope() {
    _pickScopeDomain = null;
    _pickScopePath = null;
    _pickScopeGroupPaths = null;
    _treeKey.currentState?.clearPickScope();
  }

  void _pickRandomLink() {
    // If a search collection is selected, pick from its matches
    if (_treeSelection.searchIndex != null && _treeSelection.searchIndex! < _searchResults.length) {
      final (_, matches) = _searchResults[_treeSelection.searchIndex!];
      if (matches.isEmpty) return;
      final links = matches.map((m) => m.$3).toList();
      final picked = links[DateTime.now().millisecondsSinceEpoch % links.length];
      _previewLink(picked);
      return;
    }

    // Save the pick scope from current selection (only if not already in a pick session)
    if (_pickScopeDomain == null && _pickScopePath == null && _pickScopeGroupPaths == null) {
      _pickScopeDomain = _treeSelection.domain;
      _pickScopePath = _treeSelection.path;
      _pickScopeGroupPaths = _treeSelection.groupPaths;
    }

    // Use the saved pick scope for collecting links
    final scopeDomain = _pickScopeDomain;
    final scopePath = _pickScopePath;
    final scopeGroupPaths = _pickScopeGroupPaths;

    final links = <String>[];
    final data = _appData.data;

    void collectFromPath(String domain, String path) {
      final pathData = data[domain]?[path];
      if (pathData == null) return;
      for (final url in pathData.keys) {
        if (url == '__meta__') continue;
        final info = pathData[url];
        if (info != null && info['hidden'] == true) continue;
        links.add(url);
      }
    }

    void collectFromDomain(String domain) {
      final domainData = data[domain];
      if (domainData == null) return;
      for (final path in domainData.keys) {
        collectFromPath(domain, path);
      }
    }

    if (scopeGroupPaths != null && scopeDomain != null) {
      // Group scope: collect from all paths in the group
      for (final path in scopeGroupPaths) {
        collectFromPath(scopeDomain, path);
      }
    } else if (scopePath != null && scopeDomain != null) {
      collectFromPath(scopeDomain, scopePath);
    } else if (scopeDomain != null) {
      collectFromDomain(scopeDomain);
    } else {
      // Nothing selected — collect from all domains
      for (final domain in data.keys) {
        collectFromDomain(domain);
      }
    }

    if (links.isEmpty) return;

    // Separate by priority: unrated first, then Uhm (4), then others
    final unrated = <String>[];
    final uhm = <String>[];
    final others = <String>[];
    for (final url in links) {
      final location = _findLinkLocation(url);
      if (location == null) continue;
      final (domain, path) = location;
      final rating = _appData.getRating(domain, path, url);
      if (rating == null) {
        unrated.add(url);
      } else if (rating == 4) {
        uhm.add(url);
      } else if (rating != 5) {
        others.add(url);
      }
    }

    final pool = unrated.isNotEmpty ? unrated : (uhm.isNotEmpty ? uhm : others);
    if (pool.isEmpty) return;

    final random = DateTime.now().millisecondsSinceEpoch;
    final picked = pool[random % pool.length];

    // Open its preview (do NOT change tree selection — keep the pick scope node selected)
    _previewLink(picked);
  }

  // ============================================================
  // Preview
  // ============================================================

  Future<void> _previewLink(String url) async {
    if (kIsWeb) return;
    if (!isK2sFileUrl(url)) {
      stderr.writeln('[preview] Not a k2s file URL: $url');
      _loadUrl(url);
      return;
    }

    final fileId = extractFileId(url)!;
    stderr.writeln('[preview] fileId=$fileId from url=$url');

    _currentPreviewK2sUrl = url;

    final imageUrls = <String>[];
    final client = HttpClient();

    for (int i = 0; ; i++) {
      final idx = i.toString().padLeft(2, '0');
      final imageUrl = 'https://static-cache.k2s.cc/sprite/$fileId/$idx.jpeg';
      stderr.writeln('[preview] probing $imageUrl ...');
      try {
        final request = await client.headUrl(Uri.parse(imageUrl));
        final response = await request.close();
        await response.drain();
        stderr.writeln('[preview]   status=${response.statusCode}');
        if (response.statusCode == 200) {
          imageUrls.add(imageUrl);
        } else {
          break;
        }
      } catch (e) {
        stderr.writeln('[preview]   error: $e');
        break;
      }
    }

    client.close();
    stderr.writeln('[preview] found ${imageUrls.length} images');
    _currentPreviewTotalFrames = imageUrls.length * 25;

    if (imageUrls.isEmpty) {
      // Fallback: fetch source_page and show its images
      final location = _findLinkLocation(url);
      String? sourcePage;
      if (location != null) {
        final (d, p) = location;
        sourcePage = _appData.getSourcePage(d, p, url);
      }
      if (sourcePage != null) {
        _showSourcePage(sourcePage, url);
      } else {
        _loadUrl(url);
      }
      return;
    }

    final totalFrames = imageUrls.length * 25;
    final previewTitle = linkLabel(url).replaceAll("'", "\\'").replaceAll('&', '&amp;').replaceAll('<', '&lt;');
    // Get rating for the preview
    int? previewRating;
    final previewLoc = _findLinkLocation(url);
    if (previewLoc != null) {
      final (d, p) = previewLoc;
      previewRating = _appData.getRating(d, p, url);
    }
    final isPreviewVr = previewLoc != null && _appData.getVr(previewLoc.$1, previewLoc.$2, url);
    final ratingColorsHex = ['#f44336', '#ffeb3b', '#4caf50', '#2196f3', '#9e9e9e'];
    final ratingLabels = ['Super', 'Top', 'Ok', 'Uhm', 'Bad'];
    final ratingDotsHtml = List.generate(5, (i) {
      final active = previewRating == i + 1;
      final border = active ? '2px solid #fff' : '1px solid #666';
      return '<span class="rate-dot" data-rating="${i+1}" style="display:inline-block;width:14px;height:14px;border-radius:50%;background:${ratingColorsHex[i]};border:$border;cursor:pointer;margin:0 1px;" title="${ratingLabels[i]}"></span>';
    }).join('');
    // VR sprites: show only left half, stretched to full width
    final imgStyle = isPreviewVr
        ? 'width:200%;max-width:200%;display:block;margin:0 auto;cursor:crosshair;'
        : 'max-width:100%;display:block;margin:0 auto;cursor:crosshair;';
    final containerStyle = isPreviewVr
        ? 'overflow:hidden;width:100%;'
        : '';
    final imgTags = imageUrls
        .asMap()
        .entries
        .map((e) => '<div class="sprite-container" style="$containerStyle"><img data-idx="${e.key}" src="${e.value}" style="$imgStyle"></div>')
        .join('\n');
    // Build JSON array of sprite URLs for JS
    final spriteUrlsJson = imageUrls.map((u) => '"$u"').join(',');
    // Build JSON array of existing tags for overlay
    final existingTags = <Map<String, dynamic>>[];
    if (previewLoc != null) {
      final (d, p) = previewLoc;
      existingTags.addAll(_appData.getTags(d, p, url));
    }
    final tagsJson = existingTags.map((t) {
      final tagKey = t['tag'] as String;
      final frame = t['frame'] as int;
      final emojiIdx = kTagKeys.indexOf(tagKey);
      final emoji = emojiIdx >= 0 ? kTagEmojis[emojiIdx] : '?';
      return '{"frame":$frame,"emoji":"$emoji"}';
    }).join(',');
    final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body{margin:0;padding:0;background:#111;}
::-webkit-scrollbar{width:10px;}
::-webkit-scrollbar-track{background:#222;}
::-webkit-scrollbar-thumb{background:#666;border-radius:5px;}
::-webkit-scrollbar-thumb:hover{background:#888;}
#speedbar{background:#000;padding:4px 12px;position:fixed;top:0;left:0;right:0;z-index:100;}
#speedbar .title-row{display:flex;gap:6px;align-items:center;margin-bottom:2px;}
#speedbar .controls-row{display:flex;gap:8px;align-items:center;}
#sprites{padding:8px;padding-top:70px;}
#speedbar button{background:#333;color:#fff;border:1px solid #666;border-radius:4px;padding:4px 12px;font:13px sans-serif;cursor:pointer;}
#speedbar button:hover{background:#555;}
#speedbar button.active{background:#f44336;border-color:#f44336;}
#speedbar input[type=range]{flex:1;cursor:pointer;accent-color:#f44336;}
#speedbar #frameinfo{color:#aaa;font:12px sans-serif;white-space:nowrap;}
#speedbar #filename{color:#ccc;font:11px sans-serif;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;}
#player-overlay{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:#000;z-index:998;flex-direction:column;justify-content:center;align-items:center;}
#player-overlay.active{display:flex;}
#player-frame{width:80vw;height:80vh;background-size:cover;background-position:center;background-repeat:no-repeat;cursor:pointer;}
#tagpopup{position:fixed;background:rgba(0,0,0,0.9);color:#fff;padding:8px 12px;border-radius:8px;font:14px sans-serif;display:none;z-index:999;cursor:default;}
#tagpopup .label{font-size:11px;color:#aaa;margin-bottom:6px;text-align:center;}
#tagpopup .row{display:flex;gap:6px;justify-content:center;margin-bottom:4px;}
#tagpopup .tag{font-size:22px;cursor:pointer;}
#tagpopup .tag:hover{transform:scale(1.3);}
#tagpopup .rate{width:24px;height:24px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:bold;color:#fff;cursor:pointer;}
#tagpopup .rate:hover{transform:scale(1.3);}
.sprite-container{position:relative;display:inline-block;width:100%;}
.sprite-container img{display:block;width:100%;}
.tag-marker{position:absolute;font-size:14px;text-shadow:0 0 3px #000,0 0 6px #000;pointer-events:none;z-index:10;}
</style></head>
<body>
<div id="speedbar">
  <div class="title-row">
    <span id="filename">$previewTitle</span>
    <span id="ratingdots">$ratingDotsHtml</span>
  </div>
  <div class="controls-row">
    <button onclick="startPreview(1)">1/s</button>
    <button onclick="startPreview(2)">2/s</button>
    <button onclick="startPreview(4)">4/s</button>
    <button onclick="startPreview(8)">8/s</button>
    <input type="range" id="scrubslider" min="0" max="0" value="0" oninput="onScrub(this.value)">
    <button onclick="stopPreview()">Stop</button>
    <span id="frameinfo"></span>
  </div>
</div>
<div id="player-overlay" onclick="closeOverlay()">
  <div id="player-frame" onclick="event.stopPropagation();onFrameClick(event);"></div>
</div>
<div id="sprites">
$imgTags
</div>
<div id="tagpopup">
  <div class="label"></div>
  <div class="row" id="tagrow"></div>
  <div class="row" id="raterow"></div>
</div>
<script>
var gridSize = 5;
var framesPerImage = gridSize * gridSize;
var totalFrames = $totalFrames;
var isVr = ${isPreviewVr ? 'true' : 'false'};
var spriteUrls = [$spriteUrlsJson];
var previewTimer = null;
var previewFrame = 0;
var overlay = document.getElementById('player-overlay');
var playerFrame = document.getElementById('player-frame');
var frameinfo = document.getElementById('frameinfo');

var scrubslider = document.getElementById('scrubslider');
scrubslider.max = totalFrames - 1;

function startPreview(fps) {
  if (previewTimer) { clearInterval(previewTimer); previewTimer = null; }
  previewFrame = 0;
  overlay.classList.add('active');
  document.querySelectorAll('#speedbar button').forEach(function(b){ b.classList.remove('active'); });
  event.target.classList.add('active');
  showPreviewFrame();
  previewTimer = setInterval(function() {
    previewFrame++;
    if (previewFrame >= totalFrames) previewFrame = 0;
    showPreviewFrame();
  }, 1000 / fps);
}

function stopPreview() {
  if (previewTimer) { clearInterval(previewTimer); previewTimer = null; }
  overlay.classList.remove('active');
  document.querySelectorAll('#speedbar button').forEach(function(b){ b.classList.remove('active'); });
  frameinfo.textContent = '';
}

function closeOverlay() {
  stopPreview();
}

function showPreviewFrame() {
  var spriteIdx = Math.floor(previewFrame / framesPerImage);
  var posInSprite = previewFrame % framesPerImage;
  var row = Math.floor(posInSprite / gridSize);
  var col = posInSprite % gridSize;
  var url = spriteUrls[spriteIdx];
  playerFrame.style.backgroundImage = 'url(' + url + ')';
  if (isVr) {
    // VR: show left half of cell — double horizontal zoom, offset to left half
    playerFrame.style.backgroundSize = (gridSize * 200) + '% ' + (gridSize * 100) + '%';
    playerFrame.style.backgroundPosition = (col * 200 / (gridSize * 2 - 1)) + '% ' + (row * 100 / (gridSize - 1)) + '%';
  } else {
    playerFrame.style.backgroundSize = (gridSize * 100) + '% ' + (gridSize * 100) + '%';
    playerFrame.style.backgroundPosition = (col * 100 / (gridSize - 1)) + '% ' + (row * 100 / (gridSize - 1)) + '%';
  }
  var secs = previewFrame * 10;
  var mm = Math.floor(secs / 60);
  var ss = secs % 60;
  var timeStr = mm + ':' + (ss < 10 ? '0' : '') + ss;
  frameinfo.textContent = 'Frame ' + previewFrame + '/' + totalFrames + ' (' + timeStr + ')';
  scrubslider.value = previewFrame;
}

function onScrub(val) {
  if (previewTimer) { clearInterval(previewTimer); previewTimer = null; }
  document.querySelectorAll('#speedbar button').forEach(function(b){ b.classList.remove('active'); });
  overlay.classList.add('active');
  previewFrame = parseInt(val);
  showPreviewFrame();
}

function onFrameClick(e) {
  showPopup(previewFrame, e.clientX, e.clientY);
  if (window.FrameClick) FrameClick.postMessage('' + previewFrame);
}

var tagpopup = document.getElementById('tagpopup');
var tagrow = document.getElementById('tagrow');
var raterow = document.getElementById('raterow');
var popupTimer;
var currentFrame = -1;

var tags = [
  {key:'blo', emoji:'\u{1F48B}'},
  {key:'dog', emoji:'\u{1F415}'},
  {key:'fro', emoji:'\u{1F600}'},
  {key:'bak', emoji:'\u{1F351}'},
  {key:'ass', emoji:'\u{1F3AF}'},
  {key:'cum', emoji:'\u{1F4A6}'}
];
var ratings = [
  {n:1, label:'Super', color:'#f44336'},
  {n:2, label:'Top', color:'#ffc107'},
  {n:3, label:'Ok', color:'#4caf50'},
  {n:4, label:'Uhm', color:'#2196f3'},
  {n:5, label:'Bad', color:'#9e9e9e'}
];

function buildPopup() {
  tagrow.innerHTML = '';
  raterow.innerHTML = '';
  tags.forEach(function(t) {
    var span = document.createElement('span');
    span.className = 'tag';
    span.textContent = t.emoji;
    span.addEventListener('click', function(e) {
      e.stopPropagation();
      e.preventDefault();
      var f = currentFrame;
      hidePopup();
      FrameClick.postMessage('tag:' + f + ':' + t.key);
    });
    tagrow.appendChild(span);
  });
  ratings.forEach(function(r) {
    var div = document.createElement('div');
    div.className = 'rate';
    div.style.background = r.color;
    div.textContent = r.n;
    div.title = r.label;
    div.addEventListener('click', function(e) {
      e.stopPropagation();
      e.preventDefault();
      hidePopup();
      FrameClick.postMessage('rate:' + r.n);
    });
    raterow.appendChild(div);
  });
}
buildPopup();

// Speedbar rating dots click handler
document.querySelectorAll('.rate-dot').forEach(function(dot) {
  dot.addEventListener('click', function(e) {
    e.stopPropagation();
    var r = this.getAttribute('data-rating');
    FrameClick.postMessage('rate:' + r);
    // Update visual: set active border
    document.querySelectorAll('.rate-dot').forEach(function(d) {
      d.style.border = '1px solid #666';
    });
    this.style.border = '2px solid #fff';
  });
});

tagpopup.addEventListener('click', function(e) { e.stopPropagation(); });
tagpopup.addEventListener('contextmenu', function(e) { e.stopPropagation(); e.preventDefault(); });

function showPopup(frame, x, y) {
  currentFrame = frame;
  var secs = frame * 10;
  var mm = Math.floor(secs / 60);
  var ss = secs % 60;
  var time = mm + ':' + (ss < 10 ? '0' : '') + ss;
  tagpopup.querySelector('.label').textContent = 'Frame ' + frame + ' (' + time + ')';
  tagpopup.style.left = Math.min(x + 12, window.innerWidth - 280) + 'px';
  tagpopup.style.top = Math.max(y - 80, 0) + 'px';
  tagpopup.style.display = 'block';
  clearTimeout(popupTimer);
  popupTimer = setTimeout(hidePopup, 3000);
}

function hidePopup() {
  tagpopup.style.display = 'none';
  clearTimeout(popupTimer);
}

function calcFrame(img, e) {
  var rect = img.getBoundingClientRect();
  var x = e.clientX - rect.left;
  var y = e.clientY - rect.top;
  // In VR mode, image is 200% width so rect.width is 2x container; double x ratio
  var xRatio = isVr ? (x / rect.width * 2) : (x / rect.width);
  var col = Math.floor(xRatio * gridSize);
  var row = Math.floor(y / rect.height * gridSize);
  if (col >= gridSize) col = gridSize - 1;
  if (row >= gridSize) row = gridSize - 1;
  var idx = parseInt(img.getAttribute('data-idx'));
  return idx * framesPerImage + row * gridSize + col;
}

document.querySelectorAll('#sprites img').forEach(function(img) {
  img.addEventListener('click', function(e) {
    var frame = calcFrame(img, e);
    showPopup(frame, e.clientX, e.clientY);
    if (window.FrameClick) FrameClick.postMessage('' + frame);
  });
  img.addEventListener('dblclick', function(e) {
    e.preventDefault();
    var frame = calcFrame(img, e);
    hidePopup();
    if (window.FrameClick) FrameClick.postMessage('dblclick:' + frame);
  });
  img.addEventListener('contextmenu', function(e) {
    e.preventDefault();
    var frame = calcFrame(img, e);
    showPopup(frame, e.clientX, e.clientY);
    if (window.FrameRightClick) FrameRightClick.postMessage('' + frame);
  });
});

// Overlay existing tag emojis on sprite grids
var existingTags = [$tagsJson];
existingTags.forEach(function(t) {
  var spriteIdx = Math.floor(t.frame / framesPerImage);
  var posInSprite = t.frame % framesPerImage;
  var row = Math.floor(posInSprite / gridSize);
  var col = posInSprite % gridSize;
  var container = document.querySelectorAll('.sprite-container')[spriteIdx];
  if (!container) return;
  var marker = document.createElement('span');
  marker.className = 'tag-marker';
  marker.textContent = t.emoji;
  marker.style.left = isVr ? (col / gridSize * 200) + '%' : (col / gridSize * 100) + '%';
  marker.style.top = (row / gridSize * 100) + '%';
  container.appendChild(marker);
});
</script>
</body>
</html>
''';

    _browserController.loadHtmlString(html, baseUrl: 'https://static-cache.k2s.cc');
  }


  // ============================================================
  // Build UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final totalHeight = constraints.maxHeight;
          final leftWidth = totalWidth * _verticalSplit;
          final rightWidth = totalWidth - leftWidth - 6; // 6px for divider

          return Row(
            children: [
              // Left pane
              SizedBox(
                width: leftWidth,
                child: _recentsServerActive
                    ? _buildServerLeftPane(leftWidth, totalHeight)
                    : _buildLeftPane(leftWidth, totalHeight),
              ),
              // Vertical divider (draggable)
              GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _verticalSplit += details.delta.dx / totalWidth;
                    _verticalSplit = _verticalSplit.clamp(0.15, 0.85);
                  });
                },
                child: Container(
                  width: 6,
                  color: Colors.grey[400],
                  child: Center(
                    child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey[600]),
                  ),
                ),
              ),
              // Right pane
              SizedBox(
                width: rightWidth,
                child: _recentsServerActive
                    ? _buildBrowser()
                    : _buildRightPane(rightWidth, totalHeight),
              ),
            ],
          );
        },
      ),
    ),
    if (_flashMessage != null)
      Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_flashMessage!,
                style: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.none, fontWeight: FontWeight.normal),
              ),
            ),
          ),
        ),
      ),
    ],
    );
  }

  Widget _buildServerLeftPane(double width, double totalHeight) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(2.0),
      ),
      child: _buildTreeView(),
    );
  }

  Widget _buildLeftPane(double width, double totalHeight) {
    final topHeight = totalHeight * _leftHorizontalSplit;
    final bottomHeight = totalHeight - topHeight - 6;

    return Column(
      children: [
        SizedBox(
          height: topHeight,
          child: _buildVideoPlayer(0),
        ),
        // Horizontal divider (draggable)
        GestureDetector(
          onVerticalDragUpdate: (details) {
            setState(() {
              _leftHorizontalSplit += details.delta.dy / totalHeight;
              _leftHorizontalSplit = _leftHorizontalSplit.clamp(0.15, 0.85);
            });
          },
          child: Container(
            height: 6,
            color: Colors.grey[400],
            child: Center(
              child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey[600]),
            ),
          ),
        ),
        SizedBox(
          height: bottomHeight,
          child: _buildVideoPlayer(1),
        ),
      ],
    );
  }

  Widget _buildRightPane(double width, double totalHeight) {
    final topHeight = totalHeight * _rightHorizontalSplit;
    final bottomHeight = totalHeight - topHeight - 6;

    return Column(
      children: [
        SizedBox(
          height: topHeight,
          child: _buildBrowser(),
        ),
        // Horizontal divider (draggable)
        GestureDetector(
          onVerticalDragUpdate: (details) {
            setState(() {
              _rightHorizontalSplit += details.delta.dy / totalHeight;
              _rightHorizontalSplit = _rightHorizontalSplit.clamp(0.15, 0.85);
            });
          },
          child: Container(
            height: 6,
            color: Colors.grey[400],
            child: Center(
              child: Icon(Icons.drag_indicator, size: 16, color: Colors.grey[600]),
            ),
          ),
        ),
        SizedBox(
          height: bottomHeight,
          child: _buildTreeView(),
        ),
      ],
    );
  }

  // ============================================================
  // Video Player Widget
  // ============================================================
  int? _getRatingForK2sUrl(String k2sUrl) {
    final location = _findLinkLocation(k2sUrl);
    if (location == null) return null;
    final (domain, path) = location;
    return _appData.getRating(domain, path, k2sUrl);
  }

  bool _getVrForK2sUrl(String k2sUrl) {
    final location = _findLinkLocation(k2sUrl);
    if (location == null) return false;
    final (domain, path) = location;
    return _appData.getVr(domain, path, k2sUrl);
  }

  Widget _buildVideoPlayer(int index) {
    if (kIsWeb) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('Video player not available on web',
              style: TextStyle(color: Colors.white54)),
        ),
      );
    }
    final currentK2sUrl = _playerK2sUrls[index];
    final validRecentAll = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    // Deduplicate by k2sUrl (keep first occurrence)
    final seen = <String>{};
    final validRecent = <RecentVideo>[];
    for (final v in validRecentAll) {
      if (seen.add(v.k2sUrl)) validRecent.add(v);
    }
    // If current video is not in the filtered list, don't set it as dropdown value
    final dropdownValue = (currentK2sUrl != null && validRecent.any((v) => v.k2sUrl == currentK2sUrl))
        ? currentK2sUrl : '__empty__';
    final isVr = currentK2sUrl != null && _getVrForK2sUrl(currentK2sUrl);
    // Sort: % mode = completion then rating; 👍 mode = rating then completion
    validRecent.sort((a, b) {
      final ra = _getRatingForK2sUrl(a.k2sUrl) ?? 99;
      final rb = _getRatingForK2sUrl(b.k2sUrl) ?? 99;
      if (_dropdownSortByRating[index]) {
        if (ra != rb) return ra.compareTo(rb);
        return a.watchedPercent.compareTo(b.watchedPercent);
      } else {
        if (a.watchedPercent != b.watchedPercent) return a.watchedPercent.compareTo(b.watchedPercent);
        return ra.compareTo(rb);
      }
    });

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Bar with radio button, dropdown, and lens icon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            color: Colors.grey[200],
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() { _dropdownSortByRating[index] = !_dropdownSortByRating[index]; });
                  },
                  child: Tooltip(
                    message: _dropdownSortByRating[index] ? 'Sorted by rating' : 'Sorted by %',
                    child: Text(
                      _dropdownSortByRating[index] ? '\u{1F44D}' : '%',
                      style: TextStyle(fontSize: _dropdownSortByRating[index] ? 16 : 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    itemHeight: null,
                    hint: const Text('Select video...', style: TextStyle(fontSize: 12)),
                    value: dropdownValue,
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(
                        value: '__empty__',
                        child: Text('Empty', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      ),
                      ...validRecent.map((v) {
                      final rating = _getRatingForK2sUrl(v.k2sUrl);
                      Color? bgColor;
                      if (rating != null && rating >= 1 && rating <= 5) {
                        bgColor = kRatingColors[rating - 1].withOpacity(0.2);
                      }
                      final pct = v.watchedPercent;
                      return DropdownMenuItem<String>(
                        value: v.k2sUrl,
                        child: Container(
                          color: bgColor,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                  final video = _recentVideos.firstWhere((rv) => rv.k2sUrl == v.k2sUrl);
                                  setState(() { _selectedPlayer = index; });
                                  _switchVideo(index, video);
                                },
                                child: _spriteThumbnail(v.k2sUrl, v.maxPosition, width: 267, height: 150) ?? const SizedBox(width: 267, height: 150),
                              ),
                              const SizedBox(width: 4),
                              Text('$pct% ',
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    _previewLink(v.k2sUrl);
                                  },
                                  child: Text(v.title,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    ],
                    selectedItemBuilder: (context) {
                      return <Widget>[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Empty', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        ),
                        ...validRecent.map((v) {
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Text(v.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          );
                        }),
                      ];
                    },
                    onChanged: (value) {
                      if (value == '__empty__') {
                        _savePlayerPositions();
                        _players[index].stop();
                        setState(() {
                          _playerK2sUrls[index] = null;
                          _playerDownloadUrls[index] = null;
                          _playerTotalFrames[index] = 0;
                        });
                        return;
                      }
                      if (value != null) {
                        final video = _recentVideos.firstWhere((v) => v.k2sUrl == value);
                        setState(() {
                          _selectedPlayer = index;
                        });
                        _switchVideo(index, video);
                      }
                    },
                    isDense: true,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Radio<int>(
                    value: index,
                    groupValue: _selectedPlayer,
                    onChanged: (value) {
                      setState(() {
                        _selectedPlayer = value!;
                      });
                      _playerFocusNodes[value!].requestFocus();
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Surprise: play random video from recents
                IconButton(
                  icon: const Icon(Icons.casino, size: 16),
                  onPressed: validRecent.isNotEmpty ? () {
                    setState(() { _selectedPlayer = index; });
                    final random = DateTime.now().millisecondsSinceEpoch;
                    final picked = validRecent[random % validRecent.length];
                    _switchVideo(index, picked);
                  } : null,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                  tooltip: 'Random video',
                ),
                // Collection: show origin path in tree
                IconButton(
                  icon: const Icon(Icons.folder_open, size: 16),
                  onPressed: currentK2sUrl != null ? () {
                    final location = _findLinkLocation(currentK2sUrl);
                    if (location == null) return;
                    final (domain, path) = location;
                    _treeKey.currentState?.navigateToLink(domain, path, currentK2sUrl);
                    _clearPickScope();
                    _currentPreviewK2sUrl = null;
                  } : null,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                  tooltip: 'Show in tree',
                ),
                // Rating buttons
                if (currentK2sUrl != null) ...[
                  const SizedBox(width: 2),
                  for (int ri = 0; ri < 5; ri++)
                    GestureDetector(
                      onTap: () {
                        final location = _findLinkLocation(currentK2sUrl);
                        if (location != null) {
                          final (domain, path) = location;
                          setState(() {
                            _appData.setRating(domain, path, currentK2sUrl, ri + 1);
                          });
                          _saveData();
                          // Rating Bad (5/grey): remove from recents and play next
                          if (ri + 1 == 5) {
                            _removeAndPlayNext(index, currentK2sUrl);
                          }
                        }
                      },
                      onSecondaryTap: () {
                        // Right-click: rate the selected tree item (path or link)
                        final sel = _treeSelection;
                        if (sel.link != null && sel.path != null && sel.domain != null) {
                          setState(() {
                            _appData.setRating(sel.domain!, sel.path!, sel.link!, ri + 1);
                          });
                          _saveData();
                        } else if (sel.path != null && sel.domain != null) {
                          setState(() {
                            _appData.setPathRating(sel.domain!, sel.path!, ri + 1);
                          });
                          _saveData();
                        }
                      },
                      child: Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: kRatingColors[ri],
                          borderRadius: BorderRadius.circular(2),
                          border: (() {
                            final location = _findLinkLocation(currentK2sUrl);
                            if (location != null) {
                              final (domain, path) = location;
                              final r = _appData.getRating(domain, path, currentK2sUrl);
                              if (r == ri + 1) {
                                return Border.all(color: Colors.white, width: 2);
                              }
                            }
                            return Border.all(color: Colors.grey[600]!, width: 0.5);
                          })(),
                        ),
                      ),
                    ),
                ],
                // Tag buttons to tag at current position
                if (currentK2sUrl != null) ...[
                  const SizedBox(width: 2),
                  for (int ti = 0; ti < kTagKeys.length; ti++)
                    GestureDetector(
                      onTap: () {
                        final location = _findLinkLocation(currentK2sUrl);
                        if (location == null) return;
                        final (domain, path) = location;
                        final frame = _players[index].state.position.inSeconds ~/ 10;
                        setState(() {
                          final currentRating = _appData.getRating(domain, path, currentK2sUrl);
                          if (currentRating == null || currentRating == 4 || currentRating == 5) {
                            _appData.setRating(domain, path, currentK2sUrl, 3);
                          }
                          _appData.addTag(domain, path, currentK2sUrl, frame, kTagKeys[ti]);
                        });
                        _saveData();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 1),
                        child: Text(kTagEmojis[ti], style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ],
                // Existing tag count
                if (currentK2sUrl != null) ...[
                  Builder(builder: (_) {
                    final location = _findLinkLocation(currentK2sUrl);
                    if (location == null) return const SizedBox.shrink();
                    final (domain, path) = location;
                    final tags = _appData.getTags(domain, path, currentK2sUrl);
                    if (tags.isEmpty) return const SizedBox.shrink();
                    return Text('(${tags.length})', style: TextStyle(fontSize: 10, color: Colors.grey[600]));
                  }),
                ],
                if (currentK2sUrl != null) ...[
                  Builder(builder: (_) {
                    final rv = _recentVideos.where((v) => v.k2sUrl == currentK2sUrl).firstOrNull;
                    final pct = rv?.watchedPercent ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('$pct%', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    );
                  }),
                ],
                IconButton(
                  icon: const Icon(Icons.search, size: 18),
                  onPressed: currentK2sUrl != null ? () {
                    setState(() {
                      _selectedPlayer = index;
                    });
                    _openPreviewForPlayer(index);
                  } : null,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Preview',
                ),
                GestureDetector(
                  onTap: validRecent.isNotEmpty ? () => _goToAdjacentVideo(index, validRecent, 1) : null,
                  onSecondaryTap: validRecent.isNotEmpty ? () => _goToAdjacentVideo(index, validRecent, -1) : null,
                  child: Tooltip(
                    message: 'Next / right-click: Previous',
                    child: Icon(Icons.skip_next, size: 18,
                      color: validRecent.isNotEmpty ? Colors.grey[700] : Colors.grey[400]),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    _players[index].playOrPause();
                  },
                  onSecondaryTap: () {
                    _players[index].stop();
                    setState(() {
                      _playerK2sUrls[index] = null;
                      _playerTotalFrames[index] = 0;
                    });
                  },
                  child: Tooltip(
                    message: 'Play/Pause — right-click: Stop & clear',
                    child: Icon(
                      _players[index].state.playing ? Icons.pause : Icons.play_arrow,
                      size: 18,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: currentK2sUrl != null ? () {
                    final location = _findLinkLocation(currentK2sUrl);
                    if (location != null) {
                      final (domain, path) = location;
                      final current = _appData.getVr(domain, path, currentK2sUrl);
                      _appData.setVr(domain, path, currentK2sUrl, !current);
                      _saveData();
                      setState(() {});
                    }
                  } : null,
                  child: Tooltip(
                    message: 'VR 180°',
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: (currentK2sUrl != null && _getVrForK2sUrl(currentK2sUrl)) ? Colors.green[100] : null,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.vrpano, size: 18,
                        color: currentK2sUrl != null ? Colors.grey[700] : Colors.grey[400]),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: currentK2sUrl != null ? () {
                    _removeAndPlayNext(index, currentK2sUrl);
                  } : null,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Remove from recents',
                ),
              ],
            ),
          ),
          // Video area
          Expanded(
            child: RepaintBoundary(
              child: Focus(
                focusNode: _playerFocusNodes[index],
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: isVr ? 0.5 : 1.0,
                    child: Video(
                      controller: _videoControllers[index],
                      controls: (state) => GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          setState(() { _selectedPlayer = index; });
                          final pos = _players[index].state.position;
                          _players[index].seek(pos + const Duration(seconds: 2));
                        },
                        onDoubleTap: () {
                          setState(() { _selectedPlayer = index; });
                          final pos = _players[index].state.position;
                          _players[index].seek(pos + const Duration(seconds: 10));
                        },
                        onSecondaryTap: () {
                          setState(() { _selectedPlayer = index; });
                          final pos = _players[index].state.position;
                          final target = pos - const Duration(seconds: 10);
                          _players[index].seek(target < Duration.zero ? Duration.zero : target);
                        },
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Seek bar
          SizedBox(
            height: 20,
            child: StreamBuilder<Duration>(
              stream: _players[index].stream.position,
              builder: (ctx, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = _players[index].state.duration;
                final maxMs = dur.inMilliseconds.toDouble();
                final curMs = pos.inMilliseconds.toDouble();
                return SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: Colors.red,
                    inactiveTrackColor: Colors.grey[800]!,
                    thumbColor: Colors.red,
                    overlayColor: Colors.red.withValues(alpha: 0.3),
                  ),
                  child: Slider(
                    value: maxMs > 0 ? curMs.clamp(0, maxMs) : 0,
                    min: 0,
                    max: maxMs > 0 ? maxMs : 1,
                    onChanged: (v) {
                      _players[index].seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                );
              },
            ),
          ),
          // Tag bar (emoticons)
          GestureDetector(
            onSecondaryTapUp: (details) {
              _showLocalTagPopup(context, details.globalPosition, index);
            },
            child: Container(
            height: 28,
            color: Colors.grey[100],
            child: LayoutBuilder(
              builder: (context, constraints) {
                final k2sUrl = _playerK2sUrls[index];
                if (k2sUrl == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      Text('Tags: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  );
                }
                final location = _findLinkLocation(k2sUrl);
                if (location == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      Text('Tags: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  );
                }
                final (domain, path) = location;
                final tags = _appData.getTags(domain, path, k2sUrl);
                if (tags.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      Text('Tags: ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                  );
                }
                // Use player total frames, or estimate from player duration, or from max tag frame
                var totalFrames = _playerTotalFrames[index];
                if (totalFrames == 0) {
                  final dur = _players[index].state.duration.inSeconds;
                  if (dur > 0) totalFrames = dur ~/ 10;
                }
                if (totalFrames == 0) {
                  final maxFrame = tags.fold<int>(0, (m, t) => (t['frame'] as int) > m ? (t['frame'] as int) : m);
                  totalFrames = maxFrame + 10; // add margin
                }
                final barWidth = constraints.maxWidth;
                // Extract fileId for sprite hover
                final fileId = extractFileId(k2sUrl) ?? '';
                return Stack(
                  children: tags.map((tag) {
                    final frame = tag['frame'] as int;
                    final tagKey = tag['tag'] as String;
                    final tagIdx = kTagKeys.indexOf(tagKey);
                    final emoji = tagIdx >= 0 ? kTagEmojis[tagIdx] : '?';
                    final pos = (frame / totalFrames) * barWidth;
                    return Positioned(
                      left: pos.clamp(0, barWidth - 20),
                      top: 2,
                      child: SpriteHoverTag(
                        emoji: emoji,
                        frame: frame,
                        fileId: fileId,
                        timeLabel: formatTime(frame * 10),
                        fontSize: 16,
                        onTap: () {
                          final seekMs = frame * 10 * 1000;
                          _players[index].seek(Duration(milliseconds: seekMs));
                        },
                        onSecondaryTap: () {
                          setState(() {
                            _appData.removeTag(domain, path, k2sUrl, frame, tagKey);
                          });
                          _saveData();
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          ),
        ],
      ),
    );
  }

  void _showLocalTagPopup(BuildContext context, Offset globalPosition, int playerIdx) {
    final k2sUrl = _playerK2sUrls[playerIdx];
    if (k2sUrl == null) return;
    final location = _findLinkLocation(k2sUrl);
    if (location == null) return;
    final (domain, path) = location;

    // Calculate current frame from player position
    final positionSec = _players[playerIdx].state.position.inSeconds;
    final frame = positionSec ~/ 10;

    final overlay = globalOverlay;
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Transparent barrier to dismiss
            Positioned.fill(
              child: GestureDetector(
                onTap: () { if (entry.mounted) entry.remove(); },
                onSecondaryTap: () { if (entry.mounted) entry.remove(); },
                child: Container(color: Colors.transparent),
              ),
            ),
            // Popup near mouse position
            Positioned(
              left: globalPosition.dx,
              top: globalPosition.dy - 80,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tag emojis row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(kTagKeys.length, (i) {
                          return GestureDetector(
                            onTap: () {
                              if (entry.mounted) entry.remove();
                              setState(() {
                                if (_appData.getRating(domain, path, k2sUrl) == null) {
                                  _appData.setRating(domain, path, k2sUrl, 3);
                                }
                                _appData.addTag(domain, path, k2sUrl, frame, kTagKeys[i]);
                              });
                              _saveData();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(kTagEmojis[i], style: const TextStyle(fontSize: 20)),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 6),
                      // Rating circles row
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (i) {
                          return GestureDetector(
                            onTap: () {
                              if (entry.mounted) entry.remove();
                              setState(() {
                                _appData.setRating(domain, path, k2sUrl, i + 1);
                              });
                              _saveData();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: CircleAvatar(
                                radius: 12,
                                backgroundColor: kRatingColors[i],
                                child: Text('${i + 1}',
                                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (entry.mounted) {
        try { entry.remove(); } catch (_) {}
      }
    });
  }

  // ============================================================
  // Recents Page
  // ============================================================

  void _onRecentsClick(String msg) {
    if (msg.startsWith('play:')) {
      final k2sUrl = msg.substring(5);
      final video = _recentVideos.where((v) => v.k2sUrl == k2sUrl).firstOrNull;
      if (video == null) return;
      final playerIdx = _selectedPlayer;
      _switchVideo(playerIdx, video);
      // Show the preview for this video
      _previewLink(k2sUrl);
    } else if (msg.startsWith('tag:')) {
      // format: tag:<url>:<frame>
      final rest = msg.substring(4);
      final lastColon = rest.lastIndexOf(':');
      if (lastColon < 0) return;
      final k2sUrl = rest.substring(0, lastColon);
      final frame = int.tryParse(rest.substring(lastColon + 1));
      if (frame == null) return;
      final video = _recentVideos.where((v) => v.k2sUrl == k2sUrl).firstOrNull;
      if (video == null) return;
      final playerIdx = _selectedPlayer;
      _switchVideo(playerIdx, video);
      // Seek to tagged position after video loads
      Future.delayed(const Duration(milliseconds: 800), () {
        final seekMs = frame * 10 * 1000;
        _players[playerIdx].seek(Duration(milliseconds: seekMs));
      });
      // Show the preview for this video
      _previewLink(k2sUrl);
    }
  }

  void _showRecentsPage() {
    if (kIsWeb) return;
    final html = _buildRecentsHtml(forWebServer: false);
    _browserController.loadHtmlString(html, baseUrl: 'https://static-cache.k2s.cc');
  }

  String _buildRecentsHtml({bool forWebServer = false}) {
    final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    // Sort by completion percentage (least complete first)
    validRecent.sort((a, b) => a.watchedPercent.compareTo(b.watchedPercent));

    if (validRecent.isEmpty) {
      return '''
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="background:#222;color:#aaa;font:16px sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
<p>No recent videos.</p>
</body></html>''';
    }

    final ratingColorsCss = ['#f44336', '#ffc107', '#4caf50', '#2196f3', '#9e9e9e'];
    final tagEmojiMap = <String, String>{};
    for (int i = 0; i < kTagKeys.length; i++) {
      tagEmojiMap[kTagKeys[i]] = kTagEmojis[i];
    }

    final cards = StringBuffer();
    for (final video in validRecent) {
      final rating = _getRatingForK2sUrl(video.k2sUrl);
      final bgColor = (rating != null && rating >= 1 && rating <= 5)
          ? '${ratingColorsCss[rating - 1]}33'
          : '#333';
      final borderColor = (rating != null && rating >= 1 && rating <= 5)
          ? ratingColorsCss[rating - 1]
          : '#555';

      // Get tags for this video
      final location = _findLinkLocation(video.k2sUrl);
      final tags = <Map<String, dynamic>>[];
      if (location != null) {
        final (domain, path) = location;
        tags.addAll(_appData.getTags(domain, path, video.k2sUrl));
      }

      // Get file ID for preview image
      final fileId = extractFileId(video.k2sUrl) ?? '';

      // Escape title and URLs for HTML
      final escapedTitle = video.title.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
      final escapedK2sUrl = video.k2sUrl.replaceAll("'", "\\'");
      final escapedDownloadUrl = video.downloadUrl.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

      // Build horizontal strip of clipped sprite frames for tags + current position
      final stripHtml = StringBuffer();
      if (fileId.isNotEmpty) {
        // Most advanced position frame
        final posFrame = (video.maxPosition ~/ 10).toInt();
        // Collect all frames: tags + current position
        final frames = <Map<String, dynamic>>[];
        for (final tag in tags) {
          frames.add({'frame': tag['frame'] as int, 'tag': tag['tag'] as String});
        }
        // Add current position if not already a tagged frame
        final hasCurrentPos = frames.any((f) => f['frame'] == posFrame);
        if (!hasCurrentPos) {
          frames.add({'frame': posFrame, 'tag': '_pos'});
        }
        // Sort by frame
        frames.sort((a, b) => (a['frame'] as int).compareTo(b['frame'] as int));

        for (final f in frames) {
          final frame = f['frame'] as int;
          final tagKey = f['tag'] as String;
          final isCurrentPos = tagKey == '_pos';
          final emoji = isCurrentPos ? '' : (tagEmojiMap[tagKey] ?? '?');
          final spriteIdx = frame ~/ 25;
          final row = (frame % 25) ~/ 5;
          final col = frame % 5;
          final spriteUrl = 'https://static-cache.k2s.cc/sprite/$fileId/${spriteIdx.toString().padLeft(2, '0')}.jpeg';
          final timeSec = frame * 10;
          final mm = timeSec ~/ 60;
          final ss = timeSec % 60;
          final timeStr = '$mm:${ss.toString().padLeft(2, '0')}';
          final borderStyle = isCurrentPos ? 'border:2px solid #f44336;' : 'border:2px solid transparent;';
          stripHtml.write('''
<div class="frame-cell" data-url="$escapedK2sUrl" data-download-url="$escapedDownloadUrl" data-frame="$frame" title="$timeStr" style="$borderStyle">
  <div class="frame-clip" style="background-image:url('$spriteUrl');background-position:-${col * 120}px -${row * 90}px;background-size:600px 450px;"></div>
  ${emoji.isNotEmpty ? '<span class="frame-tag">$emoji</span>' : ''}
</div>
''');
        }
      }

      final pct = video.watchedPercent;
      final cardIdx = validRecent.indexOf(video);
      final isVr = location != null && _appData.getVr(location.$1, location.$2, video.k2sUrl);
      if (forWebServer) {
        // Rating dots
        final ratingDots = StringBuffer();
        for (int r = 1; r <= 5; r++) {
          final active = rating == r;
          final border = active ? 'border:2px solid #fff;' : 'border:2px solid transparent;';
          ratingDots.write('<span class="rating-dot" data-card="$cardIdx" data-rating="$r" style="background:${ratingColorsCss[r - 1]};$border" title="Rate $r"></span>');
        }
        final vrClass = isVr ? ' active' : '';
        cards.write('''
<div class="card" style="background:$bgColor;border-color:$borderColor;">
  <div class="title" data-url="$escapedK2sUrl" data-download-url="$escapedDownloadUrl" data-card="$cardIdx" style="background:linear-gradient(to right, ${borderColor}66 ${pct}%, transparent ${pct}%);">
    <span class="remove-btn" data-card="$cardIdx" title="Remove from recents">&times;</span>
    $escapedTitle <span class="pct">${pct}%</span>
    <span class="card-actions">$ratingDots<span class="vr-btn$vrClass" data-card="$cardIdx" title="VR 180°">VR</span></span>
  </div>
  <div class="strip" data-card="$cardIdx">$stripHtml</div>
</div>
''');
      } else {
        cards.write('''
<div class="card" style="background:$bgColor;border-color:$borderColor;">
  <div class="title" data-url="$escapedK2sUrl" data-download-url="$escapedDownloadUrl" data-card="$cardIdx" style="background:linear-gradient(to right, ${borderColor}66 ${pct}%, transparent ${pct}%);">$escapedTitle <span class="pct">${pct}%</span></div>
  <div class="strip" data-card="$cardIdx">$stripHtml</div>
</div>
''');
      }
    }

    final scriptJs = forWebServer ? '''
document.querySelectorAll('.title').forEach(function(el) {
  el.addEventListener('click', function(e) {
    if (e.target.classList.contains('remove-btn') || e.target.classList.contains('rating-dot') || e.target.classList.contains('vr-btn')) return;
    var card = el.getAttribute('data-card');
    window.location.href = '/deovr/' + card;
  });
});
document.querySelectorAll('.remove-btn').forEach(function(btn) {
  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    var card = btn.getAttribute('data-card');
    fetch('/remove/' + card, {method:'POST'}).then(function() { location.reload(); });
  });
});
document.querySelectorAll('.rating-dot').forEach(function(dot) {
  dot.addEventListener('click', function(e) {
    e.stopPropagation();
    var card = dot.getAttribute('data-card');
    var rating = dot.getAttribute('data-rating');
    fetch('/rate/' + card + '/' + rating, {method:'POST'}).then(function() { location.reload(); });
  });
});
document.querySelectorAll('.vr-btn').forEach(function(btn) {
  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    var card = btn.getAttribute('data-card');
    fetch('/vr/' + card, {method:'POST'}).then(function() { location.reload(); });
  });
});
// Tree browser
var treeDomain = document.getElementById('tree-domain');
var treePath = document.getElementById('tree-path');
var treeAdd = document.getElementById('tree-add');
var treeNext = document.getElementById('tree-next');
var treeEnd = document.getElementById('tree-end');
var treeAddVr = document.getElementById('tree-add-vr');
var treePreview = document.getElementById('tree-preview');
var previewTitle = document.getElementById('preview-title');
var previewStatus = document.getElementById('preview-status');
var previewImages = document.getElementById('preview-images');
var treeCount = document.getElementById('tree-count');
var currentLink = null;
fetch('/tree/domains').then(function(r){return r.json();}).then(function(domains) {
  domains.forEach(function(d) {
    var o = document.createElement('option'); o.value = d; o.textContent = d;
    treeDomain.appendChild(o);
  });
});
treeDomain.addEventListener('change', function() {
  treePath.innerHTML = '<option value="">-- collection --</option>';
  treePreview.style.display = 'none';
  treeAdd.style.display = 'none';
  treeNext.style.display = 'none';
  treeEnd.style.display = 'none';
  treeCount.textContent = '';
  currentLink = null;
  if (!treeDomain.value) { treePath.style.display = 'none'; return; }
  fetch('/tree/paths/' + encodeURIComponent(treeDomain.value)).then(function(r){return r.json();}).then(function(paths) {
    paths.forEach(function(p) {
      var o = document.createElement('option'); o.value = p; o.textContent = p;
      treePath.appendChild(o);
    });
    treePath.style.display = '';
    treeEnd.style.display = '';
  });
});
function loadPreview() {
  if (!treeDomain.value || !treePath.value) return;
  previewStatus.textContent = 'Loading...';
  previewImages.style.display = 'none';
  previewImages.innerHTML = '';
  treeAdd.disabled = true;
  treeAddVr.disabled = true;
  fetch('/tree/preview/' + encodeURIComponent(treeDomain.value) + '/' + encodeURIComponent(treePath.value))
    .then(function(r){return r.json();})
    .then(function(data) {
      if (data.empty) { previewTitle.textContent = 'No fresh links'; previewStatus.textContent = ''; return; }
      currentLink = data.link;
      var sizeStr = data.fileSize ? ' [' + data.fileSize + ']' : '';
      previewTitle.textContent = data.title + sizeStr;
      treeCount.textContent = data.totalFresh + ' fresh';
      previewStatus.textContent = '';
      treeAdd.disabled = false;
      treeAddVr.disabled = false;
      if (data.images && data.images.length > 0) {
        previewImages.innerHTML = '';
        data.images.forEach(function(url) {
          var img = document.createElement('img');
          img.style.cssText = 'height:180px;display:none;margin-right:4px;border-radius:4px;';
          img.onload = function() {
            if (img.naturalWidth > 200 && img.naturalHeight > 200) {
              img.style.display = 'inline-block';
            } else {
              img.remove();
            }
          };
          img.onerror = function() { img.remove(); };
          img.src = url;
          previewImages.appendChild(img);
        });
        previewImages.style.display = 'block';
      } else {
        previewImages.style.display = 'none';
        previewStatus.textContent = 'No preview images';
      }
    });
}
treePath.addEventListener('change', function() {
  if (!treePath.value) { treePreview.style.display = 'none'; treeAdd.style.display = 'none'; treeAddVr.style.display = 'none'; treeNext.style.display = 'none'; return; }
  treePreview.style.display = 'block';
  treeAdd.style.display = '';
  treeAddVr.style.display = '';
  treeNext.style.display = '';
  loadPreview();
});
treeNext.addEventListener('click', function() { loadPreview(); });
function doTreeAdd(vr) {
  if (!currentLink) return;
  treeAdd.disabled = true;
  treeAddVr.disabled = true;
  previewStatus.textContent = 'Adding...';
  var url = '/tree/add/' + encodeURIComponent(treeDomain.value) + '/' + encodeURIComponent(treePath.value) + '?link=' + encodeURIComponent(currentLink);
  if (vr) url += '&vr=1';
  fetch(url, {method:'POST'})
    .then(function(r){return r.json();})
    .then(function(data) {
      if (data.status === 'ok') { previewStatus.textContent = 'Added' + (vr ? ' (VR)' : '') + ': ' + data.title; }
      else if (data.status === 'already') { previewStatus.textContent = 'Already in recents'; }
      else { previewStatus.textContent = 'Error: ' + (data.message || 'unknown'); }
    });
}
treeAdd.addEventListener('click', function() { doTreeAdd(false); });
treeAddVr.addEventListener('click', function() { doTreeAdd(true); });
treeEnd.addEventListener('click', function() {
  treeDomain.value = '';
  treePath.style.display = 'none';
  treePath.innerHTML = '<option value="">-- collection --</option>';
  treePreview.style.display = 'none';
  treeAdd.style.display = 'none';
  treeAddVr.style.display = 'none';
  treeNext.style.display = 'none';
  treeEnd.style.display = 'none';
  treeCount.textContent = '';
  currentLink = null;
});''' : '''
document.querySelectorAll('.title').forEach(function(el) {
  el.addEventListener('click', function(e) {
    var url = el.getAttribute('data-url');
    FrameClick.postMessage('recents:play:' + url);
  });
});
document.querySelectorAll('.frame-cell').forEach(function(cell) {
  cell.addEventListener('click', function(e) {
    var url = cell.getAttribute('data-url');
    var frame = cell.getAttribute('data-frame');
    FrameClick.postMessage('recents:tag:' + url + ':' + frame);
  });
});''';

    return '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body { margin:0; padding:12px; background:#222; font-family:sans-serif; }
.card { border:2px solid #555; border-radius:8px; margin-bottom:12px; padding:10px; }
.title { color:#fff; font-size:14px; font-weight:bold; margin-bottom:6px; cursor:pointer; padding:4px 8px; border-radius:4px; position:relative; }
.pct { font-size:11px; color:#aaa; font-weight:normal; }
.title:hover { text-decoration:underline; }
.strip { display:flex; gap:6px; overflow-x:auto; padding:4px 0; }
.frame-cell { position:relative; flex-shrink:0; width:120px; height:90px; border-radius:4px; overflow:hidden; cursor:pointer; }
.frame-cell:hover { opacity:0.8; }
.frame-clip { width:100%; height:100%; background-repeat:no-repeat; }
.frame-tag { position:absolute; top:2px; left:2px; font-size:16px; text-shadow:0 0 3px #000, 0 0 6px #000; }
.remove-btn { cursor:pointer; color:#f44336; font-size:18px; font-weight:bold; margin-right:6px; }
.remove-btn:hover { color:#ff6659; }
.card-actions { float:right; display:inline-flex; align-items:center; gap:4px; }
.rating-dot { display:inline-block; width:14px; height:14px; border-radius:3px; cursor:pointer; }
.rating-dot:hover { opacity:0.7; }
.vr-btn { display:inline-block; font-size:10px; font-weight:bold; color:#aaa; background:#444; padding:1px 4px; border-radius:3px; cursor:pointer; margin-left:4px; }
.vr-btn.active { background:#4caf50; color:#fff; }
.vr-btn:hover { opacity:0.7; }
.deovr-link { display:inline-block; margin-bottom:12px; color:#4fc3f7; font-size:13px; text-decoration:none; }
.deovr-link:hover { text-decoration:underline; }
.tree-bar { background:#333; padding:8px 12px; margin-bottom:12px; border-radius:8px; display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
.tree-bar select { background:#444; color:#fff; border:1px solid #666; border-radius:4px; padding:4px 8px; font-size:13px; }
.tree-bar button { background:#555; color:#fff; border:none; border-radius:4px; padding:4px 12px; font-size:13px; cursor:pointer; }
.tree-bar button:hover { background:#777; }
.tree-bar button:disabled { opacity:0.4; cursor:default; }
.tree-bar .count { color:#aaa; font-size:11px; }
.tree-preview { background:#111; border:2px solid #555; border-radius:8px; margin-bottom:12px; padding:10px; display:none; }
.tree-preview .preview-title { color:#fff; font-size:14px; font-weight:bold; margin-bottom:6px; }
.tree-preview .preview-size { color:#aaa; font-size:12px; margin-left:8px; }
.tree-preview img { max-width:100%; border-radius:4px; margin-top:6px; }
.tree-preview .preview-status { color:#aaa; font-size:12px; margin-top:4px; }
</style></head>
<body>
${forWebServer ? '<a class="deovr-link" href="/deovr">/deovr</a>' : ''}
${forWebServer ? '''
<div class="tree-bar" id="tree-bar">
  <select id="tree-domain"><option value="">-- site --</option></select>
  <select id="tree-path" style="display:none;"><option value="">-- collection --</option></select>
  <span class="count" id="tree-count"></span>
  <button id="tree-add" style="display:none;" disabled>Add</button>
  <button id="tree-add-vr" style="display:none;" disabled>Add VR</button>
  <button id="tree-next" style="display:none;">Next</button>
  <button id="tree-end" style="display:none;">End</button>
</div>
<div class="tree-preview" id="tree-preview">
  <div class="preview-title" id="preview-title"></div>
  <div class="preview-status" id="preview-status"></div>
  <div id="preview-images" style="display:none;overflow-x:auto;white-space:nowrap;padding:4px 0;"></div>
</div>
''' : ''}
$cards
<script>
$scriptJs
</script>
</body>
</html>
''';
  }

  Future<void> _toggleRecentsServer() async {
    if (kIsWeb) return;
    stderr.writeln('[server] toggle called, active=$_recentsServerActive');
    if (_recentsServerActive) {
      await _recentsServer?.close();
      setState(() {
        _recentsServer = null;
        _recentsServerActive = false;
      });
      stderr.writeln('[server] stopped');
    } else {
      try {
        final server = await HttpServer.bind(InternetAddress.anyIPv4, 9999);
        setState(() {
          _recentsServer = server;
          _recentsServerActive = true;
        });
        stderr.writeln('[server] started on http://localhost:9999');
        server.listen((request) async {
          stderr.writeln('[server] ${request.method} ${request.uri.path}');
          final path = request.uri.path;
          if (path == '/deovr') {
            _handleDeovrIndex(request);
          } else if (path.startsWith('/deovr/')) {
            _handleDeovrVideo(request);
          } else if (path.startsWith('/remove/')) {
            _handleRemoveRecent(request);
          } else if (path.startsWith('/rate/')) {
            _handleRateRecent(request);
          } else if (path.startsWith('/vr/')) {
            _handleVrToggle(request);
          } else if (path == '/tree/domains') {
            _handleTreeDomains(request);
          } else if (path.startsWith('/tree/paths/')) {
            _handleTreePaths(request);
          } else if (path.startsWith('/tree/preview/')) {
            await _handleTreePreview(request);
          } else if (path.startsWith('/tree/add/')) {
            await _handleTreeAdd(request);
          } else {
            final html = _buildRecentsHtml(forWebServer: true);
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.html
              ..write(html)
              ..close();
          }
        });
      } catch (e) {
        stderr.writeln('[server] failed to start: $e');
        _showFlash('Failed to start server: $e');
      }
    }
  }

  /// Build the DeoVR feed list: VR videos first, then non-VR, each group shuffled.
  /// Caches the result per request cycle so index and video endpoints match.
  List<RecentVideo> _deovrFeedOrder = [];
  int _deovrFeedStamp = 0;

  List<RecentVideo> _buildDeovrFeed() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    // Rebuild every 60 seconds to keep the shuffle stable across index+video requests
    if (_deovrFeedOrder.isEmpty || (now - _deovrFeedStamp) > 60) {
      final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
      final vr = validRecent.where((v) => _getVrForK2sUrl(v.k2sUrl)).toList()..shuffle();
      final nonVr = validRecent.where((v) => !_getVrForK2sUrl(v.k2sUrl)).toList()..shuffle();
      _deovrFeedOrder = [...vr, ...nonVr];
      _deovrFeedStamp = now;
    }
    return _deovrFeedOrder;
  }

  void _handleDeovrIndex(HttpRequest request) {
    final validRecent = _buildDeovrFeed();

    final hostHeader = request.headers.value('host') ?? 'localhost:9999';
    final host = hostHeader.contains(':') ? hostHeader : '$hostHeader:9999';
    final list = validRecent.asMap().entries.map((e) {
      final i = e.key;
      final v = e.value;
      final fileId = extractFileId(v.k2sUrl) ?? '';
      final thumbUrl = fileId.isNotEmpty
          ? 'https://static-cache.k2s.cc/sprite/$fileId/00.jpeg'
          : '';
      return {
        'title': v.title,
        'videoLength': (v.durationSeconds).round(),
        'thumbnailUrl': thumbUrl,
        'video_url': 'http://$host/deovr/$i',
      };
    }).toList();

    final body = json.encode({
      'authorized': '1',
      'scenes': [
        {'name': 'Recents', 'list': list},
      ],
    });

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  }

  void _handleDeovrVideo(HttpRequest request) {
    final idxStr = request.uri.path.substring('/deovr/'.length);
    final idx = int.tryParse(idxStr);
    final validRecent = _buildDeovrFeed();

    if (idx == null || idx < 0 || idx >= validRecent.length) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
      return;
    }

    final v = validRecent[idx];
    final fileId = extractFileId(v.k2sUrl) ?? '';
    final thumbUrl = fileId.isNotEmpty
        ? 'https://static-cache.k2s.cc/sprite/$fileId/00.jpeg'
        : '';

    // Build timestamps from tags
    final location = _findLinkLocation(v.k2sUrl);
    final timeStamps = <Map<String, dynamic>>[];
    if (location != null) {
      final (domain, path) = location;
      final tags = _appData.getTags(domain, path, v.k2sUrl);
      for (final tag in tags) {
        final frame = tag['frame'] as int;
        final tagKey = tag['tag'] as String;
        final emojiIdx = kTagKeys.indexOf(tagKey);
        final emoji = emojiIdx >= 0 ? kTagEmojis[emojiIdx] : tagKey;
        timeStamps.add({'ts': frame * 10, 'name': '$emoji ${formatTime(frame * 10)}'});
      }
      timeStamps.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    }

    final isVr = location != null && _appData.getVr(location.$1, location.$2, v.k2sUrl);

    final body = json.encode({
      'id': idx,
      'title': v.title,
      'authorized': 1,
      'videoLength': (v.durationSeconds).round(),
      'thumbnailUrl': thumbUrl,
      'is3d': isVr,
      'screenType': isVr ? 'dome' : 'flat',
      'stereoMode': isVr ? 'sbs' : 'off',
      'encodings': [
        {
          'name': 'original',
          'videoSources': [
            {'resolution': 1080, 'url': v.downloadUrl},
          ],
        },
      ],
      'timeStamps': timeStamps,
    });

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(body)
      ..close();
  }

  void _handleRemoveRecent(HttpRequest request) {
    final idxStr = request.uri.path.substring('/remove/'.length);
    final idx = int.tryParse(idxStr);
    final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    validRecent.sort((a, b) => a.watchedPercent.compareTo(b.watchedPercent));

    if (idx == null || idx < 0 || idx >= validRecent.length) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not found')
        ..close();
      return;
    }

    final v = validRecent[idx];
    setState(() {
      _recentVideos.removeWhere((r) => r.k2sUrl == v.k2sUrl);
    });
    _saveRecent();
    stderr.writeln('[server] removed recent: ${v.title}');

    request.response
      ..statusCode = HttpStatus.ok
      ..write('OK')
      ..close();
  }

  void _handleRateRecent(HttpRequest request) {
    // /rate/<index>/<rating>
    final parts = request.uri.path.substring('/rate/'.length).split('/');
    if (parts.length != 2) {
      request.response..statusCode = HttpStatus.badRequest..write('Bad request')..close();
      return;
    }
    final idx = int.tryParse(parts[0]);
    final rating = int.tryParse(parts[1]);
    final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    validRecent.sort((a, b) => a.watchedPercent.compareTo(b.watchedPercent));

    if (idx == null || idx < 0 || idx >= validRecent.length || rating == null || rating < 1 || rating > 5) {
      request.response..statusCode = HttpStatus.notFound..write('Not found')..close();
      return;
    }

    final v = validRecent[idx];
    final location = _findLinkLocation(v.k2sUrl);
    if (location != null) {
      final (domain, path) = location;
      setState(() {
        _appData.setRating(domain, path, v.k2sUrl, rating);
      });
      _saveData();
      stderr.writeln('[server] rated ${v.title} as $rating');
    }

    request.response..statusCode = HttpStatus.ok..write('OK')..close();
  }

  void _handleVrToggle(HttpRequest request) {
    // /vr/<index>
    final idxStr = request.uri.path.substring('/vr/'.length);
    final idx = int.tryParse(idxStr);
    final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    validRecent.sort((a, b) => a.watchedPercent.compareTo(b.watchedPercent));

    if (idx == null || idx < 0 || idx >= validRecent.length) {
      request.response..statusCode = HttpStatus.notFound..write('Not found')..close();
      return;
    }

    final v = validRecent[idx];
    final location = _findLinkLocation(v.k2sUrl);
    if (location != null) {
      final (domain, path) = location;
      final current = _appData.getVr(domain, path, v.k2sUrl);
      setState(() {
        _appData.setVr(domain, path, v.k2sUrl, !current);
      });
      _saveData();
      stderr.writeln('[server] toggled VR for ${v.title}: ${!current}');
    }

    request.response..statusCode = HttpStatus.ok..write('OK')..close();
  }

  void _handleTreeDomains(HttpRequest request) {
    final classified = classifyLinks(_appData);
    final freshDomains = classified['fresh']?.keys.toList() ?? [];
    freshDomains.sort();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(json.encode(freshDomains))
      ..close();
  }

  void _handleTreePaths(HttpRequest request) {
    final domain = Uri.decodeComponent(request.uri.path.substring('/tree/paths/'.length));
    final classified = classifyLinks(_appData);
    final allPaths = classified['fresh']?[domain]?.keys.toList() ?? [];
    allPaths.sort(compareByTrailingNumber);
    final groups = groupPathsByPrefix(allPaths);
    // Return only top-level: group prefix or standalone path
    final topLevel = groups.map((g) => g.prefix ?? g.paths.first).toList();
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(json.encode(topLevel))
      ..close();
  }

  Future<void> _handleTreePreview(HttpRequest request) async {
    // /tree/preview/<domain>/<path> — returns JSON with a random fresh link's preview info
    // <path> may be a group prefix, so collect links from all matching sub-paths
    final rest = request.uri.path.substring('/tree/preview/'.length);
    final slashIdx = rest.indexOf('/');
    if (slashIdx < 0) {
      request.response..statusCode = HttpStatus.badRequest..write('Bad request')..close();
      return;
    }
    final domain = Uri.decodeComponent(rest.substring(0, slashIdx));
    final pathPrefix = Uri.decodeComponent(rest.substring(slashIdx + 1));

    final classified = classifyLinks(_appData);
    final domainPaths = classified['fresh']?[domain] ?? {};
    // Collect links from the exact path and all sub-paths starting with the prefix
    final allLinks = <(String, String)>[]; // (path, link)
    for (final entry in domainPaths.entries) {
      if (entry.key == pathPrefix || entry.key.startsWith(pathPrefix)) {
        for (final link in entry.value) {
          allLinks.add((entry.key, link));
        }
      }
    }
    if (allLinks.isEmpty) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(json.encode({'empty': true}))
        ..close();
      return;
    }

    final pick = allLinks[(DateTime.now().microsecond) % allLinks.length];
    final (path, link) = pick;
    final fileId = extractFileId(link) ?? '';
    final title = linkLabel(link);
    final sourcePage = _appData.getSourcePage(domain, path, link);
    final fileSize = _appData.getFileSize(domain, path, link);

    // Collect preview images: sprites or source page images
    final images = <String>[];
    if (fileId.isNotEmpty) {
      // Probe sprite images
      final client = HttpClient();
      for (int i = 0; ; i++) {
        final idx = i.toString().padLeft(2, '0');
        try {
          final req = await client.headUrl(Uri.parse('https://static-cache.k2s.cc/sprite/$fileId/$idx.jpeg'));
          final resp = await req.close();
          await resp.drain();
          if (resp.statusCode == 200) {
            images.add('https://static-cache.k2s.cc/sprite/$fileId/$idx.jpeg');
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
      client.close();
    }
    if (images.isEmpty && sourcePage != null) {
      // Fetch source page and extract images
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(sourcePage));
        final resp = await req.close();
        final body = await resp.transform(utf8.decoder).join();
        client.close();
        final imgPattern = RegExp(r'''(?:src|data-src)=["']([^"']+\.(?:jpg|jpeg|png|gif|webp)[^"']*)["']''', caseSensitive: false);
        for (final match in imgPattern.allMatches(body)) {
          var imgUrl = match.group(1)!;
          if (imgUrl.startsWith('//')) imgUrl = 'https:$imgUrl';
          else if (imgUrl.startsWith('/')) {
            final uri = Uri.parse(sourcePage);
            imgUrl = '${uri.scheme}://${uri.host}$imgUrl';
          }
          images.add(imgUrl);
        }
      } catch (_) {}
    }

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(json.encode({
        'link': link,
        'fileId': fileId,
        'title': title,
        'images': images,
        'fileSize': fileSize != null ? formatFileSize(fileSize) : null,
        'totalFresh': allLinks.length,
      }))
      ..close();
  }

  Future<void> _handleTreeAdd(HttpRequest request) async {
    // /tree/add/<domain>/<path>?link=<url>
    final link = request.uri.queryParameters['link'];
    if (link == null || link.isEmpty) {
      request.response..statusCode = HttpStatus.badRequest..write('Missing link')..close();
      return;
    }

    // Check if already in recents
    if (_recentVideos.any((v) => v.k2sUrl == link)) {
      request.response..statusCode = HttpStatus.ok..write(json.encode({'status': 'already'}))..close();
      return;
    }

    final downloadUrl = await _getDownloadUrl(link);
    if (downloadUrl == null) {
      request.response..statusCode = HttpStatus.ok..write(json.encode({'status': 'error', 'message': 'Could not resolve download URL'}))..close();
      return;
    }

    final title = _titleFromK2sUrl(link);
    // Probe sprites to get totalFrames
    int totalFrames = 0;
    final fileId = extractFileId(link);
    if (fileId != null) {
      final client = HttpClient();
      for (int i = 0; ; i++) {
        final idx = i.toString().padLeft(2, '0');
        try {
          final req = await client.headUrl(Uri.parse('https://static-cache.k2s.cc/sprite/$fileId/$idx.jpeg'));
          final resp = await req.close();
          await resp.drain();
          if (resp.statusCode == 200) {
            totalFrames += 25;
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
      client.close();
    }

    final recent = RecentVideo(
      k2sUrl: link,
      downloadUrl: downloadUrl,
      title: title,
      totalFrames: totalFrames,
    );
    setState(() { _recentVideos.add(recent); });
    _saveRecent();

    // Set VR if requested
    final setVr = request.uri.queryParameters['vr'] == '1';
    if (setVr) {
      final location = _findLinkLocation(link);
      if (location != null) {
        final (domain, path) = location;
        _appData.setVr(domain, path, link, true);
        _saveData();
      }
    }
    stderr.writeln('[server] added to recents${setVr ? ' (VR)' : ''}: $title');

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(json.encode({'status': 'ok', 'title': title}))
      ..close();
  }

  // ============================================================
  // Browser Widget
  // ============================================================
  Widget _buildBrowser() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Navigation bar
          Container(
            padding: const EdgeInsets.all(4.0),
            decoration: BoxDecoration(
              color: Colors.grey[200],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: kIsWeb ? null : () async {
                    if (await _browserController.canGoBack()) {
                      _browserController.goBack();
                    }
                  },
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: kIsWeb ? null : () async {
                    if (await _browserController.canGoForward()) {
                      _browserController.goForward();
                    }
                  },
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: kIsWeb ? null : () {
                    _browserController.reload();
                    setState(() {});
                  },
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.home, size: 18),
                  onPressed: () => _loadUrl('https://k2s.cc'),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: TextField(
                      controller: _addressController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Enter URL',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 0,
                        ),
                      ),
                      onSubmitted: _loadUrl,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Preview filename
                if (_currentPreviewK2sUrl != null)
                  Flexible(
                    child: Text(
                      () {
                        final loc = _findLinkLocation(_currentPreviewK2sUrl!);
                        final sz = loc != null ? _appData.getFileSize(loc.$1, loc.$2, _currentPreviewK2sUrl!) : null;
                        final prefix = sz != null ? '${formatFileSize(sz)} ' : '';
                        return '$prefix${linkLabel(_currentPreviewK2sUrl!)}';
                      }(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                if (_currentPreviewK2sUrl != null)
                  const SizedBox(width: 4),
                // Rating buttons for current preview
                for (int r = 1; r <= 5; r++)
                  GestureDetector(
                    onTap: _currentPreviewK2sUrl != null ? () => _onRatingClicked(r) : null,
                    onSecondaryTap: () {
                      // Right-click: rate the selected tree item (path or link)
                      final sel = _treeSelection;
                      if (sel.link != null && sel.path != null && sel.domain != null) {
                        setState(() {
                          _appData.setRating(sel.domain!, sel.path!, sel.link!, r);
                        });
                        _saveData();
                      } else if (sel.path != null && sel.domain != null) {
                        setState(() {
                          _appData.setPathRating(sel.domain!, sel.path!, r);
                        });
                        _saveData();
                      }
                    },
                    child: Tooltip(
                      message: kRatingLabels[r - 1],
                      child: Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(right: 2),
                        decoration: BoxDecoration(
                          color: kRatingColors[r - 1],
                          borderRadius: BorderRadius.circular(2),
                          border: (() {
                            if (_currentPreviewK2sUrl != null) {
                              final loc = _findLinkLocation(_currentPreviewK2sUrl!);
                              if (loc != null) {
                                final (d, p) = loc;
                                final cr = _appData.getRating(d, p, _currentPreviewK2sUrl!);
                                if (cr == r) return Border.all(color: Colors.white, width: 2);
                              }
                            }
                            return Border.all(color: Colors.grey[600]!, width: 0.5);
                          })(),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                IconButton(
                  icon: Icon(Icons.play_arrow, size: 18,
                    color: (_playableK2sUrl != null || _hasPlayableInfoVideo) ? Colors.green : Colors.grey[400]),
                  onPressed: _playableK2sUrl != null
                      ? _playK2sUrl
                      : _hasPlayableInfoVideo
                          ? _playCurrentInfoVideo
                          : null,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Play',
                ),
                IconButton(
                  icon: Icon(Icons.download, size: 18,
                    color: _playableK2sUrl != null ? Colors.blue : Colors.grey[400]),
                  onPressed: _playableK2sUrl != null ? _downloadK2sUrl : null,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Download',
                ),
                IconButton(
                  icon: const Icon(Icons.casino, size: 18),
                  onPressed: _pickRandomLink,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Pick random link',
                ),
                Container(
                  decoration: BoxDecoration(
                    color: _recentsServerActive ? Colors.green[100] : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: IconButton(
                    icon: Icon(_recentsServerActive ? Icons.stop : Icons.dns, size: 18),
                    onPressed: _toggleRecentsServer,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                    tooltip: _recentsServerActive ? 'Stop server (:9999)' : 'Start server (:9999)',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.schedule, size: 18),
                  onPressed: _showRecentsPage,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Recents',
                ),
              ],
            ),
          ),
          // WebView (desktop only)
          Expanded(
            child: kIsWeb
                ? Container(
                    color: Colors.grey[900],
                    child: const Center(
                      child: Text('Browser not available on web',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  )
                : WebViewWidget(controller: _browserController),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Tree View Widget
  // ============================================================
  Widget _buildTreeView() {
    return TreeView(
      key: _treeKey,
      appData: _appData,
      recentVideos: _recentVideos,
      selectedPlayer: _selectedPlayer,
      players: _players,
      currentPreviewK2sUrl: _currentPreviewK2sUrl,
      playableK2sUrl: _playableK2sUrl,
      deepExtract: _deepExtract,
      extractLooping: _extractLooping,
      extractLoopPage: _extractLoopPage,
      extractLimitController: _extractLimitController,
      searchResults: _searchResults,
      onLoadUrl: _loadUrl,
      onPreviewLink: _previewLink,
      onAddSite: _addCurrentSite,
      onAddSiteWithDialog: _addCurrentSiteWithDialog,
      onExtractLinks: _extractLinks,
      onStartExtractLoop: _startExtractLoop,
      onRemoveSelected: _removeSelected,
      onRemoveBySubstring: _removeBySubstring,
      onDedupSelected: _dedupSelected,
      onVrSelected: _vrSelected,
      onPlayK2sUrl: _playK2sUrl,
      onDeepExtractChanged: (v) => setState(() { _deepExtract = v; }),
      onSwitchVideo: _switchVideo,
      onSaveData: _saveData,
      onSaveRecent: _saveRecent,
      onSaveSearches: _saveSearches,
      onSelectionChanged: (sel) => setState(() {
        _treeSelection = sel;
        _pickScopeDomain = null;
        _pickScopePath = null;
        _pickScopeGroupPaths = null;
      }),
      onExtractLoopStop: () => setState(() { _extractLooping = false; }),
      infoData: _infoData,
      onInfoPreview: _showInfoPreview,
      onInfoPlay: _playInfoVideo,
    );
  }

  /// Get file names and sizes from K2S API for a list of file IDs.
  Future<(Map<String, String>, Map<String, int>)> _getFileNames(List<String> fileIds) async {
    final result = <String, String>{};
    final sizes = <String, int>{};
    if (kIsWeb || fileIds.isEmpty) return (result, sizes);
    // Batch in chunks of 100 to avoid API limits
    for (int i = 0; i < fileIds.length; i += 100) {
      final batch = fileIds.sublist(i, (i + 100).clamp(0, fileIds.length));
      stderr.writeln('[getFileNames] Batch ${i ~/ 100 + 1}: ${batch.length} IDs');
      try {
        final payload = <String, dynamic>{'ids': batch, 'extended_info': false};
        final token = await _getK2sToken();
        if (token != null) payload['auth_token'] = token;
        final client = HttpClient();
        final request = await client.postUrl(Uri.parse('$_k2sApiBase/getFilesInfo'));
        request.headers.contentType = ContentType.json;
        request.write(json.encode(payload));
        final response = await request.close();
        final body = await response.transform(const Utf8Decoder(allowMalformed: true)).join();
        client.close();
        final data = json.decode(body) as Map<String, dynamic>;
        if (data['status'] == 'success') {
          for (final f in (data['files'] as List<dynamic>? ?? [])) {
            if (f is Map<String, dynamic>) {
              final id = f['id'] as String?;
              final name = f['name'] as String?;
              if (id != null && name != null) result[id] = name;
              final rawSize = f['size'];
              final size = rawSize is int ? rawSize : rawSize is double ? rawSize.toInt() : rawSize is String ? int.tryParse(rawSize) : null;
              if (id != null && size != null) sizes[id] = size;
            }
          }
          stderr.writeln('[getFileNames] Batch got ${result.length} names so far');
        } else {
          stderr.writeln('[getFileNames] Batch failed: ${data['status']} ${data['message'] ?? ''}');
        }
      } catch (e) {
        stderr.writeln('[getFileNames] Batch error: $e');
      }
    }
    return (result, sizes);
  }

  /// Toggle VR flag on all links below the selected node.
  /// When the selected node is in a VR category, always clear VR.
  void _vrSelected() {
    final sel = _treeSelection;
    if (sel.domain == null) return;
    final domain = sel.domain!;
    final links = <(String, String)>[]; // (path, link)
    if (sel.link != null && sel.path != null) {
      links.add((sel.path!, sel.link!));
    } else if (sel.path != null) {
      for (final link in _appData.linksFor(domain, sel.path!)) {
        links.add((sel.path!, link));
      }
    } else if (sel.groupPaths != null) {
      for (final path in sel.groupPaths!) {
        for (final link in _appData.linksFor(domain, path)) {
          links.add((path, link));
        }
      }
    } else {
      for (final path in _appData.pathsFor(domain)) {
        for (final link in _appData.linksFor(domain, path)) {
          links.add((path, link));
        }
      }
    }
    if (links.isEmpty) return;
    // If selected node is in a VR category, always clear VR;
    // otherwise use toggle logic (any not VR → set all VR, else clear all).
    final newVr = sel.isVrCategory ? false : links.any((e) => !_appData.getVr(domain, e.$1, e.$2));
    setState(() {
      for (final (path, link) in links) {
        _appData.setVr(domain, path, link, newVr);
      }
    });
    _saveData();
    _showFlash('${newVr ? "Set" : "Cleared"} VR on ${links.length} links');
  }

  /// Dedup: remove duplicate links by file ID in the selected subtree,
  /// and rename bare URLs (without filename) using getFilesInfo.
  Future<void> _dedupSelected() async {
    final sel = _treeSelection;
    if (kIsWeb || sel.domain == null) return;
    final domain = sel.domain!;

    final log = <String>[];
    int _logCounter = 0;
    void addLog(String msg, {bool flush = false}) {
      log.add(msg);
      stderr.writeln('[dedup] $msg');
      _logCounter++;
      if (flush || _logCounter % 50 == 0) {
        _showLogPage(log);
      }
    }

    addLog('Dedup: $domain${sel.path != null ? ' / ${sel.path}' : ''}');

    // Collect all (path, link) pairs in the subtree
    final pathLinks = <(String, String)>[];
    if (sel.link != null && sel.path != null) {
      pathLinks.add((sel.path!, sel.link!));
    } else if (sel.path != null) {
      for (final link in _appData.linksFor(domain, sel.path!)) {
        pathLinks.add((sel.path!, link));
      }
    } else {
      for (final path in _appData.pathsFor(domain)) {
        for (final link in _appData.linksFor(domain, path)) {
          pathLinks.add((path, link));
        }
      }
    }

    addLog('${pathLinks.length} links to check');

    // Group by file ID, track first occurrence
    final seenIds = <String, (String, String)>{}; // id -> (path, link) of first occurrence
    final duplicates = <(String, String, String)>[]; // (path, link, id) to remove
    final needsRename = <(String, String, String)>[]; // (path, link, id) with no name or hex-ID name
    final hexIdPattern = RegExp(r'^[0-9a-fA-F]{13,}$');

    for (final (path, link) in pathLinks) {
      final id = extractFileId(link);
      if (id == null) continue;
      if (seenIds.containsKey(id)) {
        duplicates.add((path, link, id));
      } else {
        seenIds[id] = (path, link);
        // Check if name is missing/hex-ID or size is missing
        final name = _k2sLinkName(link);
        final hasSize = _appData.getFileSize(domain, path, link) != null;
        if (name.isEmpty || hexIdPattern.hasMatch(name) || !hasSize) {
          needsRename.add((path, link, id));
        }
      }
    }

    addLog('${seenIds.length} unique IDs, ${duplicates.length} duplicates, ${needsRename.length} to rename', flush: true);

    // Remove duplicates, merging info into the keeper
    int removed = 0;
    setState(() {
      for (final (path, link, id) in duplicates) {
        final (keeperPath, keeperLink) = seenIds[id]!;
        if (keeperPath == path) {
          _mergeLinkInfo(domain, path, link, keeperLink);
        }
        _appData.removeLink(domain, path, link);
        _recentVideos.removeWhere((v) => v.k2sUrl == link);
        removed++;
      }
    });
    if (removed > 0) addLog('Removed $removed duplicates', flush: true);

    // Rename bare URLs and hex-ID names by fetching real file names
    int renamed = 0;
    if (needsRename.isNotEmpty) {
      for (final (path, link, id) in needsRename) {
        final n = _k2sLinkName(link);
        addLog('  needs rename: $id ${n.isEmpty ? "(bare)" : n}');
      }
      addLog('Fetching names for ${needsRename.length} links...', flush: true);
      final ids = needsRename.map((e) => e.$3).toList();
      final (names, fileSizes) = await _getFileNames(ids);
      addLog('Got ${names.length} names from API', flush: true);
      setState(() {
        for (final (path, link, id) in needsRename) {
          final name = names[id];
          final oldName = _k2sLinkName(link);
          if (name != null && name.isNotEmpty && name != oldName) {
            final newUrl = 'https://k2s.cc/file/$id/$name';
            addLog('  ${oldName.isEmpty ? "(bare)" : oldName} -> $name');
            _appData.addLink(domain, path, newUrl);
            _mergeLinkInfo(domain, path, link, newUrl);
            _appData.removeLink(domain, path, link);
            _recentVideos.removeWhere((v) => v.k2sUrl == link);
            if (fileSizes.containsKey(id)) {
              _appData.setFileSize(domain, path, newUrl, fileSizes[id]!);
            }
            renamed++;
          } else if (name == null || name.isEmpty) {
            addLog('  $id: no name returned');
          } else {
            // Name unchanged, but still store size if available
            if (fileSizes.containsKey(id)) {
              _appData.setFileSize(domain, path, link, fileSizes[id]!);
            }
          }
        }
      });
      if (renamed > 0) addLog('Renamed $renamed links', flush: true);
    }

    // Clean multiple dots in names: keep only the last dot (before extension)
    int dotsCleaned = 0;
    setState(() {
      for (final (path, link) in pathLinks) {
        if (!_appData.data[domain]!.containsKey(path)) continue;
        if (!_appData.data[domain]![path]!.containsKey(link)) continue;
        final id = extractFileId(link);
        if (id == null) continue;
        final name = _k2sLinkName(link);
        if (name.isEmpty) continue;
        final dotCount = '.'.allMatches(name).length;
        if (dotCount <= 1) continue;
        final lastDot = name.lastIndexOf('.');
        final base = name.substring(0, lastDot).replaceAll('.', '');
        final ext = name.substring(lastDot);
        final cleanName = '$base$ext';
        final newUrl = 'https://k2s.cc/file/$id/$cleanName';
        if (newUrl != link) {
          addLog('  dots: $name -> $cleanName');
          _appData.addLink(domain, path, newUrl);
          _mergeLinkInfo(domain, path, link, newUrl);
          _appData.removeLink(domain, path, link);
          _recentVideos.removeWhere((v) => v.k2sUrl == link);
          dotsCleaned++;
        }
      }
    });
    if (dotsCleaned > 0) addLog('Cleaned dots in $dotsCleaned links', flush: true);

    // Normalize paths: merge paths with trailing slash into their normalized form
    int normalizedPaths = 0;
    setState(() {
      for (final path in List<String>.from(_appData.pathsFor(domain))) {
        final normalized = AppData.normalizePath(path);
        if (normalized != path) {
          addLog('  path: $path -> $normalized');
          // Move all links from old path to normalized path
          _appData.data[domain]!.putIfAbsent(normalized, () => {});
          final links = Map<String, dynamic>.from(_appData.data[domain]![path] ?? {});
          for (final entry in links.entries) {
            _appData.data[domain]![normalized]!.putIfAbsent(entry.key, () => entry.value);
          }
          _appData.data[domain]!.remove(path);
          // Selection will be refreshed via tree rebuild
          normalizedPaths++;
        }
      }
    });
    if (normalizedPaths > 0) addLog('Normalized $normalizedPaths paths', flush: true);

    // Remove empty paths and domains
    int removedPaths = 0;
    int removedDomains = 0;
    setState(() {
      for (final path in List<String>.from(_appData.pathsFor(domain))) {
        if (_appData.linksFor(domain, path).isEmpty) {
          _appData.removePath(domain, path);
          removedPaths++;
        }
      }
      if (_appData.pathsFor(domain).isEmpty) {
        _appData.removeDomain(domain);
        removedDomains++;
      }
    });
    if (removedPaths > 0) addLog('Removed $removedPaths empty paths');
    if (removedDomains > 0) addLog('Removed empty domain: $domain');

    _saveData();
    final parts = <String>[];
    if (removed > 0) parts.add('$removed removed');
    if (renamed > 0) parts.add('$renamed renamed');
    if (dotsCleaned > 0) parts.add('$dotsCleaned dots cleaned');
    if (normalizedPaths > 0) parts.add('$normalizedPaths paths normalized');
    if (removedPaths > 0) parts.add('$removedPaths empty paths');
    final summary = parts.isEmpty ? 'No changes' : parts.join(', ');
    addLog('');
    addLog('Done: $summary', flush: true);

    // List all remaining link names
    final remainingLinks = <String>[];
    if (sel.path != null && _appData.data[domain] != null) {
      remainingLinks.addAll(_appData.linksFor(domain, sel.path!));
    } else if (_appData.data[domain] != null) {
      for (final path in _appData.pathsFor(domain)) {
        remainingLinks.addAll(_appData.linksFor(domain, path));
      }
    }
    if (remainingLinks.isNotEmpty) {
      addLog('');
      addLog('${remainingLinks.length} links:');
      final names = <String>[];
      for (final link in remainingLinks) {
        final name = _k2sLinkName(link);
        addLog('  $name');
        names.add(name);
      }
      // Save to dedup.txt
      try {
        final dataPath = await _getDataFilePath();
        final dedupPath = '${File(dataPath).parent.path}/dedup.txt';
        await File(dedupPath).writeAsString(names.join('\n'));
        addLog('');
        addLog('Saved to $dedupPath');
      } catch (e) {
        addLog('Error saving dedup.txt: $e');
      }
    }
  }

}

