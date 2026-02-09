import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// Tag and rating constants
const List<String> kTagKeys = ['blo', 'dog', 'fro', 'bak', 'ass', 'cum'];
const List<String> kTagEmojis = ['\u{1F48B}', '\u{1F415}', '\u{1F600}', '\u{1F351}', '\u{1F3AF}', '\u{1F4A6}'];
const List<String> kRatingLabels = ['Super', 'Top', 'Ok', 'Uhm', 'Bad'];
final List<Color> kRatingColors = [Colors.red, Colors.amber, Colors.green, Colors.blue, Colors.grey];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();

  final primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final screenWidth = primaryDisplay.size.width;
  final screenHeight = primaryDisplay.size.height;

  final windowWidth = screenWidth * 0.9;
  WindowOptions windowOptions = WindowOptions(
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

  void addSite(String domain, String path) {
    data.putIfAbsent(domain, () => {});
    if (path.isNotEmpty && path != '/') {
      data[domain]!.putIfAbsent(path, () => {});
    }
  }

  void addLink(String domain, String path, String url) {
    data.putIfAbsent(domain, () => {});
    data[domain]!.putIfAbsent(path, () => {});
    data[domain]![path]!.putIfAbsent(url, () => {});
  }

  void removeLink(String domain, String path, String url) {
    data[domain]?[path]?.remove(url);
  }

  void removePath(String domain, String path) {
    data[domain]?.remove(path);
  }

  void removeDomain(String domain) {
    data.remove(domain);
  }

  List<String> get domains => data.keys.toList();

  List<String> pathsFor(String domain) => data[domain]?.keys.toList() ?? [];

  List<String> linksFor(String domain, String path) =>
      data[domain]?[path]?.keys.toList() ?? [];

  List<String> visibleLinksFor(String domain, String path) {
    final entries = data[domain]?[path]?.entries
        .where((e) => e.value['hidden'] != true && e.value['rating'] != 5 && !e.key.toLowerCase().endsWith('.rar'))
        .toList() ?? [];
    // Sort: rated first (ascending by rating), then unrated
    entries.sort((a, b) {
      final ra = a.value['rating'] as int?;
      final rb = b.value['rating'] as int?;
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return 0;
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

  // Recent videos
  List<RecentVideo> _recentVideos = [];
  String _recentFilePath = '';

  // Tree selection
  String? _selectedDomain;
  String? _selectedPath;
  String? _selectedLink;

  // Tree expand/collapse state
  final Set<String> _expandedDomains = {};
  final Set<String> _expandedPaths = {}; // stored as "domain\tpath"

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
    _addressController.text = _currentUrl;

    // Periodically update max position and percentage
    _positionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _savePlayerPositions();
      if (mounted) setState(() {});
    });

    // Listen for player errors (e.g. expired download links)
    for (int i = 0; i < 2; i++) {
      final idx = i;
      _players[i].stream.error.listen((error) {
        stderr.writeln('[player$idx] error: $error');
        _onPlayerError(idx);
      });
    }

    _browserController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
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

  @override
  void dispose() {
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
    super.dispose();
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
    final match = RegExp(r'https://k2s\.cc/file/([^/]+)').firstMatch(k2sUrl);
    if (match == null) return null;

    final fileId = match.group(1)!;
    final token = await _getK2sToken();
    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No token found. Run "uv run util.py link <url>" first to generate .token')),
        );
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
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = json.decode(body) as Map<String, dynamic>;
      if (data['status'] == 'success') {
        return data['url'] as String;
      } else {
        stderr.writeln('[k2s] getUrl failed: $data');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('getUrl failed: ${data['message'] ?? data}')),
          );
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
    const prefix = 'https://k2s.cc/file/';
    if (url.startsWith(prefix)) {
      final rest = url.substring(prefix.length);
      final parts = rest.split('/');
      if (parts.length > 1 && parts.last.isNotEmpty) {
        return parts.sublist(1).join('/');
      }
      return parts.first;
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

    // Play the video and auto-select the other player
    setState(() {
      _selectedPlayer = 1 - playerIdx;
      _playerK2sUrls[playerIdx] = k2sUrl;
      _playerDownloadUrls[playerIdx] = downloadUrl;
      _playerTotalFrames[playerIdx] = _currentPreviewTotalFrames;
    });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$reason: $title')),
      );
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
    _removeAndPlayNext(playerIdx, k2sUrl, reason: 'Download expired');
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

  void _switchVideo(int playerIdx, RecentVideo video, {double? seekPosition}) {
    // Save current position
    _savePlayerPositions();

    setState(() {
      // Auto-select the other player for next video
      _selectedPlayer = 1 - playerIdx;
      _playerK2sUrls[playerIdx] = video.k2sUrl;
      _playerDownloadUrls[playerIdx] = video.downloadUrl;
      _playerTotalFrames[playerIdx] = video.totalFrames;
    });

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

  void _onFrameRightClicked(int frame) {
    // Popup shown in JS, no navigation needed
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tag: no preview URL')),
        );
      }
      return;
    }
    final location = _findLinkLocation(k2sUrl);
    stderr.writeln('[tag] location=$location');
    if (location == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tag: link not found in data for $k2sUrl')),
        );
      }
      return;
    }
    final (domain, path) = location;
    setState(() {
      // Auto-rate green (3=Ok) if previously unrated
      if (_appData.getRating(domain, path, k2sUrl) == null) {
        _appData.setRating(domain, path, k2sUrl, 3);
      }
      _appData.addTag(domain, path, k2sUrl, frame, tagKey);
    });
    final tags = _appData.getTags(domain, path, k2sUrl);
    stderr.writeln('[tag] after addTag, tags=$tags totalFrames=${_playerTotalFrames}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tag added: $tagKey at frame $frame (${tags.length} total)')),
      );
    }
    _saveData();
  }

  void _onRatingClicked(int rating) {
    final k2sUrl = _currentPreviewK2sUrl;
    if (k2sUrl == null) return;
    final location = _findLinkLocation(k2sUrl);
    if (location == null) return;
    final (domain, path) = location;
    setState(() {
      _appData.setRating(domain, path, k2sUrl, rating);
    });
    _saveData();
  }

  // ============================================================
  // Browser & URL
  // ============================================================

  void _loadUrl(String url) {
    String urlToLoad = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      urlToLoad = 'https://$url';
    }
    _browserController.loadRequest(Uri.parse(urlToLoad));
  }

  void _addCurrentSite() {
    final uri = Uri.tryParse(_currentUrl);
    if (uri == null) return;

    final domain = uri.host;
    final path = uri.path;

    setState(() {
      _appData.addSite(domain, path);
    });
    _saveData();
  }

  Future<Map<String, bool>> _checkFilesAvailability(List<String> fileIds) async {
    final result = <String, bool>{};
    if (fileIds.isEmpty) return result;

    try {
      final payload = <String, dynamic>{'ids': fileIds, 'extended_info': false};
      final token = await _getK2sToken();
      if (token != null) {
        payload['auth_token'] = token;
      }

      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('$_k2sApiBase/getFilesInfo'));
      request.headers.contentType = ContentType.json;
      request.write(json.encode(payload));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      final data = json.decode(body) as Map<String, dynamic>;
      if (data['status'] == 'success') {
        final files = data['files'] as List<dynamic>? ?? [];
        for (final f in files) {
          if (f is Map<String, dynamic>) {
            final id = f['id'] as String?;
            final available = f['is_available'] as bool? ?? false;
            if (id != null) {
              result[id] = available;
            }
          }
        }
      } else {
        stderr.writeln('[k2s] getFilesInfo failed: $data');
      }
    } catch (e) {
      stderr.writeln('[k2s] getFilesInfo error: $e');
    }
    return result;
  }

  String? _extractFileId(String url) {
    final match = RegExp(r'https://k2s\.cc/file/([^/]+)').firstMatch(url);
    return match?.group(1);
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

  String _formatTime(int totalSeconds) {
    final mm = totalSeconds ~/ 60;
    final ss = totalSeconds % 60;
    return '$mm:${ss.toString().padLeft(2, '0')}';
  }

  Future<void> _extractLinks() async {
    try {
      final uri = Uri.tryParse(_currentUrl);
      if (uri == null) return;

      final domain = uri.host;
      final path = uri.path;

      final prefixesJson = json.encode(_extractPrefixes);
      final jsCode = '''
        (function() {
          var prefixes = $prefixesJson;
          var links = document.getElementsByTagName('a');
          var matchingHrefs = [];
          for (var i = 0; i < links.length; i++) {
            var href = links[i].href;
            if (href) {
              for (var j = 0; j < prefixes.length; j++) {
                if (href.startsWith(prefixes[j])) {
                  matchingHrefs.push(href);
                  break;
                }
              }
            }
          }
          return JSON.stringify(matchingHrefs);
        })()
      ''';

      final result = await _browserController.runJavaScriptReturningResult(jsCode);
      String resultString = result.toString();
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = resultString.substring(1, resultString.length - 1);
      }
      resultString = resultString.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');

      final List<dynamic> hrefs = json.decode(resultString);
      final hrefStrings = hrefs.map((e) => e.toString()).toList();

      // Extract file IDs and check availability
      final urlToId = <String, String>{};
      for (final href in hrefStrings) {
        final id = _extractFileId(href);
        if (id != null) urlToId[href] = id;
      }

      final availability = await _checkFilesAvailability(urlToId.values.toSet().toList());

      setState(() {
        _appData.addSite(domain, path);
        int added = 0;
        int removed = 0;

        for (final href in hrefStrings) {
          final id = urlToId[href];
          if (id == null) continue;
          final isAvailable = availability[id] ?? false;
          final existingLinks = _appData.linksFor(domain, path);
          final alreadyExists = existingLinks.contains(href);

          if (isAvailable) {
            if (!alreadyExists) {
              _appData.addLink(domain, path, href);
              added++;
            }
          } else {
            if (alreadyExists) {
              // Remove unavailable, but preserve hidden state (don't touch hidden links)
              final wasHidden = _appData.isHidden(domain, path, href);
              if (!wasHidden) {
                _appData.removeLink(domain, path, href);
                removed++;
              }
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Extracted: $added added, $removed removed (${hrefStrings.length} found)')),
          );
        }
      });
      _saveData();
    } catch (e) {
      stderr.writeln('Error extracting links: $e');
    }
  }

  void _removeSelected() {
    if (_selectedLink != null && _selectedPath != null && _selectedDomain != null) {
      setState(() {
        _appData.removeLink(_selectedDomain!, _selectedPath!, _selectedLink!);
        _selectedLink = null;
      });
      _saveData();
    } else if (_selectedPath != null && _selectedDomain != null) {
      _showConfirmDialog('Remove path "$_selectedPath" and all its links?', () {
        setState(() {
          _appData.removePath(_selectedDomain!, _selectedPath!);
          _selectedPath = null;
          _selectedLink = null;
        });
        _saveData();
      });
    } else if (_selectedDomain != null) {
      _showConfirmDialog('Remove website "$_selectedDomain" and all its content?', () {
        setState(() {
          _appData.removeDomain(_selectedDomain!);
          _selectedDomain = null;
          _selectedPath = null;
          _selectedLink = null;
        });
        _saveData();
      });
    }
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
  // Preview
  // ============================================================

  Future<void> _previewLink(String url) async {
    final k2sPrefix = 'https://k2s.cc/file/';
    if (!url.startsWith(k2sPrefix)) {
      stderr.writeln('[preview] URL does not start with $k2sPrefix: $url');
      _loadUrl(url);
      return;
    }

    final rest = url.substring(k2sPrefix.length);
    final fileId = rest.split('/').first;
    stderr.writeln('[preview] fileId=$fileId from url=$url');

    _currentPreviewK2sUrl = url;

    // Auto-rate blue (4=Uhm) if previously unrated
    final location = _findLinkLocation(url);
    if (location != null) {
      final (domain, path) = location;
      if (_appData.getRating(domain, path, url) == null) {
        setState(() {
          _appData.setRating(domain, path, url, 4);
        });
        _saveData();
      }
    }

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
      _loadUrl(url);
      return;
    }

    final imgTags = imageUrls
        .asMap()
        .entries
        .map((e) => '<img data-idx="${e.key}" src="${e.value}" style="max-width:100%;display:block;margin:0 auto 8px auto;cursor:crosshair;">')
        .join('\n');
    final html = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><style>
body{margin:0;padding:8px;background:#111;}
#tagpopup{position:fixed;background:rgba(0,0,0,0.9);color:#fff;padding:8px 12px;border-radius:8px;font:14px sans-serif;display:none;z-index:999;cursor:default;}
#tagpopup .label{font-size:11px;color:#aaa;margin-bottom:6px;text-align:center;}
#tagpopup .row{display:flex;gap:6px;justify-content:center;margin-bottom:4px;}
#tagpopup .tag{font-size:22px;cursor:pointer;}
#tagpopup .tag:hover{transform:scale(1.3);}
#tagpopup .rate{width:24px;height:24px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:bold;color:#fff;cursor:pointer;}
#tagpopup .rate:hover{transform:scale(1.3);}
</style></head>
<body>
$imgTags
<div id="tagpopup">
  <div class="label"></div>
  <div class="row" id="tagrow"></div>
  <div class="row" id="raterow"></div>
</div>
<script>
var gridSize = 5;
var framesPerImage = gridSize * gridSize;
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
  var col = Math.floor(x / rect.width * gridSize);
  var row = Math.floor(y / rect.height * gridSize);
  if (col >= gridSize) col = gridSize - 1;
  if (row >= gridSize) row = gridSize - 1;
  var idx = parseInt(img.getAttribute('data-idx'));
  return idx * framesPerImage + row * gridSize + col;
}

document.querySelectorAll('img').forEach(function(img) {
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
</script>
</body>
</html>
''';

    _browserController.loadHtmlString(html);
  }


  /// Extract display label for a k2s link
  String _linkLabel(String url) {
    const prefix = 'https://k2s.cc/file/';
    if (url.startsWith(prefix)) {
      final rest = url.substring(prefix.length);
      final parts = rest.split('/');
      if (parts.length > 1 && parts.last.isNotEmpty) {
        return parts.sublist(1).join('/');
      }
      return parts.first; // the <id>
    }
    return url;
  }

  // ============================================================
  // Build UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                child: _buildLeftPane(leftWidth, totalHeight),
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
                child: _buildRightPane(rightWidth, totalHeight),
              ),
            ],
          );
        },
      ),
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

  Widget _buildVideoPlayer(int index) {
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
        ? currentK2sUrl : null;
    // Sort: rated first (ascending by rating), then most recent first
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
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text('Select video...', style: TextStyle(fontSize: 12)),
                    value: dropdownValue,
                    items: validRecent.map((v) {
                      final rating = _getRatingForK2sUrl(v.k2sUrl);
                      Color? bgColor;
                      if (rating != null && rating >= 1 && rating <= 5) {
                        bgColor = kRatingColors[rating - 1].withOpacity(0.2);
                      }
                      return DropdownMenuItem<String>(
                        value: v.k2sUrl,
                        child: Container(
                          color: bgColor,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Text(v.title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
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
                IconButton(
                  icon: const Icon(Icons.access_time, size: 18),
                  onPressed: _showRecentsPage,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip: 'Recents',
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
            child: Focus(
              focusNode: _playerFocusNodes[index],
              child: GestureDetector(
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
                child: Video(controller: _videoControllers[index]),
              ),
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
                final fileId = _extractFileId(k2sUrl) ?? '';
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
                      child: _SpriteHoverTag(
                        emoji: emoji,
                        frame: frame,
                        fileId: fileId,
                        timeLabel: _formatTime(frame * 10),
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

    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        return Stack(
          children: [
            // Transparent barrier to dismiss
            Positioned.fill(
              child: GestureDetector(
                onTap: () => entry.remove(),
                onSecondaryTap: () => entry.remove(),
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
                              entry.remove();
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
                              entry.remove();
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
      if (entry.mounted) {
        entry.remove();
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
    final validRecent = _recentVideos.where((v) => !v.isExpired && _getRatingForK2sUrl(v.k2sUrl) != 5).toList();
    // Sort: rated first (ascending by rating), then most recent first
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

    if (validRecent.isEmpty) {
      _browserController.loadHtmlString('''
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="background:#222;color:#aaa;font:16px sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
<p>No recent videos.</p>
</body></html>''');
      return;
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
      final k2sPrefix = 'https://k2s.cc/file/';
      String fileId = '';
      if (video.k2sUrl.startsWith(k2sPrefix)) {
        final rest = video.k2sUrl.substring(k2sPrefix.length);
        fileId = rest.split('/').first;
      }
      final previewImgUrl = fileId.isNotEmpty
          ? 'https://static-cache.k2s.cc/sprite/$fileId/00.jpeg'
          : '';

      // Escape title for HTML
      final escapedTitle = video.title.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
      final escapedK2sUrl = video.k2sUrl.replaceAll("'", "\\'");

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
<div class="frame-cell" data-url="$escapedK2sUrl" data-frame="$frame" title="$timeStr" style="$borderStyle">
  <div class="frame-clip" style="background-image:url('$spriteUrl');background-position:-${col * 120}px -${row * 90}px;background-size:600px 450px;"></div>
  ${emoji.isNotEmpty ? '<span class="frame-tag">$emoji</span>' : ''}
</div>
''');
        }
      }

      final pct = video.watchedPercent;
      cards.write('''
<div class="card" style="background:$bgColor;border-color:$borderColor;">
  <div class="title" data-url="$escapedK2sUrl" style="background:linear-gradient(to right, ${borderColor}66 ${pct}%, transparent ${pct}%);">$escapedTitle <span class="pct">${pct}%</span></div>
  <div class="strip">$stripHtml</div>
</div>
''');
    }

    final html = '''
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
</style></head>
<body>
$cards
<script>
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
});
</script>
</body>
</html>
''';

    _browserController.loadHtmlString(html);
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
                  onPressed: () async {
                    if (await _browserController.canGoBack()) {
                      _browserController.goBack();
                    }
                  },
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  onPressed: () async {
                    if (await _browserController.canGoForward()) {
                      _browserController.goForward();
                    }
                  },
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => _browserController.reload(),
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
                if (_sites.isNotEmpty)
                  SizedBox(
                    width: 90,
                    child: DropdownButton<String>(
                      value: _selectedSite,
                      hint: const Text('Site', style: TextStyle(fontSize: 12)),
                      isExpanded: true,
                      isDense: true,
                      items: _sites.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.key, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null && _sites.containsKey(newValue)) {
                          setState(() {
                            _selectedSite = newValue;
                          });
                          _loadUrl(_sites[newValue]!);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
          // WebView
          Expanded(
            child: WebViewWidget(controller: _browserController),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Tree View Widget
  // ============================================================
  Widget _buildTreeView() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // Tree content
          Expanded(
            child: _appData.domains.isEmpty
                ? const Center(
                    child: Text('No data. Use "Add" or "Extract" to populate.',
                        style: TextStyle(color: Colors.grey)))
                : ListView(
                    padding: const EdgeInsets.all(4),
                    children: _buildTreeNodes(),
                  ),
          ),
          // Button bar
          Container(
            padding: const EdgeInsets.all(6.0),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(top: BorderSide(color: Colors.grey[400]!)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _addCurrentSite,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _extractLinks,
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('Extract', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (_selectedDomain != null) ? _removeSelected : null,
                  icon: const Icon(Icons.delete, size: 16),
                  label: const Text('Remove', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    backgroundColor: Colors.red[100],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showRecentsPage,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Recents', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTreeNodes() {
    final nodes = <Widget>[];

    for (final domain in _appData.domains) {
      final isDomainSelected =
          _selectedDomain == domain && _selectedPath == null && _selectedLink == null;
      final isDomainExpanded = _expandedDomains.contains(domain);
      final hasDomainChildren = _appData.pathsFor(domain).isNotEmpty;

      nodes.add(
        _TreeNode(
          level: 0,
          icon: Icons.language,
          label: domain,
          selected: isDomainSelected,
          expanded: hasDomainChildren ? isDomainExpanded : null,
          onToggle: hasDomainChildren ? () {
            setState(() {
              if (isDomainExpanded) {
                _expandedDomains.remove(domain);
              } else {
                _expandedDomains.add(domain);
              }
            });
          } : null,
          onTap: () {
            setState(() {
              _selectedDomain = domain;
              _selectedPath = null;
              _selectedLink = null;
            });
            _loadUrl('https://$domain');
          },
        ),
      );

      if (!isDomainExpanded) continue;

      for (final path in _appData.pathsFor(domain)) {
        final isPathSelected =
            _selectedDomain == domain && _selectedPath == path && _selectedLink == null;
        final pathKey = '$domain\t$path';
        final isPathExpanded = _expandedPaths.contains(pathKey);
        final hasPathChildren = _appData.visibleLinksFor(domain, path).isNotEmpty;

        nodes.add(
          _TreeNode(
            level: 1,
            icon: Icons.folder,
            label: path,
            selected: isPathSelected,
            expanded: hasPathChildren ? isPathExpanded : null,
            onToggle: hasPathChildren ? () {
              setState(() {
                if (isPathExpanded) {
                  _expandedPaths.remove(pathKey);
                } else {
                  _expandedPaths.add(pathKey);
                }
              });
            } : null,
            onTap: () {
              setState(() {
                _selectedDomain = domain;
                _selectedPath = path;
                _selectedLink = null;
              });
              _loadUrl('https://$domain$path');
            },
          ),
        );

        if (!isPathExpanded) continue;

        for (final link in _appData.visibleLinksFor(domain, path)) {
          final isLinkSelected = _selectedDomain == domain &&
              _selectedPath == path &&
              _selectedLink == link;
          final rating = _appData.getRating(domain, path, link);
          Color? ratingColor;
          if (rating != null && rating >= 1 && rating <= 5) {
            ratingColor = kRatingColors[rating - 1];
          }

          // Build tag emoji widgets for this link
          final linkTags = _appData.getTags(domain, path, link);
          final linkTagWidgets = <Widget>[];
          final linkFileId = _extractFileId(link) ?? '';
          for (final tag in linkTags) {
            final frame = tag['frame'] as int;
            final tagKey = tag['tag'] as String;
            final tagIdx = kTagKeys.indexOf(tagKey);
            final emoji = tagIdx >= 0 ? kTagEmojis[tagIdx] : '?';
            linkTagWidgets.add(
              _SpriteHoverTag(
                emoji: emoji,
                frame: frame,
                fileId: linkFileId,
                timeLabel: _formatTime(frame * 10),
                fontSize: 12,
                onTap: () {
                  // Switch to this video and seek to tagged position
                  final video = _recentVideos.where((v) => v.k2sUrl == link).firstOrNull;
                  if (video != null) {
                    final playerIdx = _selectedPlayer;
                    _switchVideo(playerIdx, video);
                    Future.delayed(const Duration(milliseconds: 800), () {
                      _players[playerIdx].seek(Duration(milliseconds: frame * 10 * 1000));
                    });
                  }
                  _previewLink(link);
                },
              ),
            );
          }

          nodes.add(
            _TreeNode(
              level: 2,
              icon: Icons.link,
              label: _linkLabel(link),
              selected: isLinkSelected,
              backgroundColor: ratingColor,
              tagWidgets: linkTagWidgets.isNotEmpty ? linkTagWidgets : null,
              onTap: () {
                setState(() {
                  _selectedDomain = domain;
                  _selectedPath = path;
                  _selectedLink = link;
                });
                _previewLink(link);
              },
              onSecondaryTap: () {
                setState(() {
                  _appData.setHidden(domain, path, link, true);
                  _recentVideos.removeWhere((v) => v.k2sUrl == link);
                });
                _saveData();
                _saveRecent();
              },
            ),
          );
        }
      }
    }

    return nodes;
  }
}

// ============================================================
// Global registry to close all sprite hover overlays
// ============================================================
final Set<OverlayEntry> _activeSpriteOverlays = {};

void _closeAllSpriteHovers() {
  for (final entry in _activeSpriteOverlays.toList()) {
    if (entry.mounted) entry.remove();
  }
  _activeSpriteOverlays.clear();
}

// ============================================================
// Sprite Hover Tag Widget - shows clipped sprite frame on hover
// ============================================================
class _SpriteHoverTag extends StatefulWidget {
  final String emoji;
  final int frame;
  final String fileId;
  final String timeLabel;
  final double fontSize;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  const _SpriteHoverTag({
    required this.emoji,
    required this.frame,
    required this.fileId,
    required this.timeLabel,
    this.fontSize = 16,
    this.onTap,
    this.onSecondaryTap,
  });

  @override
  State<_SpriteHoverTag> createState() => _SpriteHoverTagState();
}

class _SpriteHoverTagState extends State<_SpriteHoverTag> {
  OverlayEntry? _overlayEntry;
  Timer? _autoCloseTimer;
  bool _disposed = false;

  void _showSpriteOverlay(Offset globalPosition) {
    _closeAllSpriteHovers();
    if (_disposed || !mounted) return;
    if (widget.fileId.isEmpty) return;

    final spriteIndex = widget.frame ~/ 25;
    final row = (widget.frame % 25) ~/ 5;
    final col = widget.frame % 5;
    final spriteUrl = 'https://static-cache.k2s.cc/sprite/${widget.fileId}/${spriteIndex.toString().padLeft(2, '0')}.jpeg';

    const cellDisplaySize = 160.0;
    const spriteSize = cellDisplaySize * 5;

    final entry = OverlayEntry(
      builder: (ctx) {
        return Positioned(
          left: globalPosition.dx + 16,
          top: globalPosition.dy - cellDisplaySize - 10,
          child: IgnorePointer(
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: cellDisplaySize,
                height: cellDisplaySize,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(4),
                ),
                clipBehavior: Clip.hardEdge,
                child: OverflowBox(
                  maxWidth: spriteSize,
                  maxHeight: spriteSize,
                  alignment: Alignment.topLeft,
                  child: Transform.translate(
                    offset: Offset(-col * cellDisplaySize, -row * cellDisplaySize),
                    child: Image.network(
                      spriteUrl,
                      width: spriteSize,
                      height: spriteSize,
                      fit: BoxFit.fill,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    _overlayEntry = entry;
    _activeSpriteOverlays.add(entry);
    Overlay.of(context).insert(entry);

    // Auto-close after 2 seconds
    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer(const Duration(seconds: 2), () {
      _removeSpriteOverlay();
    });
  }

  void _removeSpriteOverlay() {
    _autoCloseTimer?.cancel();
    _autoCloseTimer = null;
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry != null) {
      _activeSpriteOverlays.remove(entry);
      if (entry.mounted) entry.remove();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _removeSpriteOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onSecondaryTap: widget.onSecondaryTap,
      child: MouseRegion(
        onEnter: (event) => _showSpriteOverlay(event.position),
        child: Tooltip(
          message: widget.timeLabel,
          child: Text(widget.emoji, style: TextStyle(fontSize: widget.fontSize)),
        ),
      ),
    );
  }
}

// ============================================================
// Sprite Animated Hover Widget - TV icon that cycles through all frames
// ============================================================
// Tree Node Widget
// ============================================================
class _TreeNode extends StatelessWidget {
  final int level;
  final IconData icon;
  final String label;
  final bool selected;
  final bool? expanded; // null = no children (no toggle shown)
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onSecondaryTap;
  final Color? backgroundColor;
  final List<Widget>? tagWidgets;

  const _TreeNode({
    required this.level,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.expanded,
    this.onToggle,
    this.onSecondaryTap,
    this.backgroundColor,
    this.tagWidgets,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      child: Container(
        padding: EdgeInsets.only(left: 16.0 * level + 4, top: 3, bottom: 3, right: 4),
        color: selected
            ? Colors.deepPurple.withOpacity(0.15)
            : backgroundColor?.withOpacity(0.2),
        child: Row(
          children: [
            if (expanded != null)
              GestureDetector(
                onTap: onToggle,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: Center(
                    child: Text(
                      expanded! ? '-' : '+',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(width: 16),
            const SizedBox(width: 2),
            Icon(icon, size: 16, color: selected ? Colors.deepPurple : Colors.grey[600]),
            if (tagWidgets != null && tagWidgets!.isNotEmpty) ...[
              const SizedBox(width: 2),
              ...tagWidgets!,
            ],
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.deepPurple : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
