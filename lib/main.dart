import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();

  // Get primary display size and calculate window dimensions (1/4 of screen)
  final primaryDisplay = await screenRetriever.getPrimaryDisplay();
  final screenWidth = primaryDisplay.size.width;
  final screenHeight = primaryDisplay.size.height;
  final windowWidth = screenWidth / 2;
  final windowHeight = screenHeight / 2;

  WindowOptions windowOptions = WindowOptions(
    size: Size(windowWidth, windowHeight),
    minimumSize: const Size(400, 300),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    // Position window at bottom right
    final x = screenWidth - windowWidth;
    final y = screenHeight - windowHeight;
    await windowManager.setPosition(Offset(x, y));
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
      title: 'Simple Browser',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const BrowserPage(),
    );
  }
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController _controller;
  final TextEditingController _addressController = TextEditingController();
  String _currentUrl = 'https://www.google.com';

  Map<String, String> _sites = {};
  List<String> _extractPrefixes = [];
  String? _selectedSite;

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _addressController.text = _currentUrl;

    _controller = WebViewController()
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
      ..loadRequest(Uri.parse(_currentUrl));
  }

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
      stdout.writeln('Config loaded: ${_sites.length} sites, ${_extractPrefixes.length} extract prefixes');
    } catch (e) {
      stderr.writeln('Error loading config: $e');
    }
  }

  void _loadUrl(String url) {
    String urlToLoad = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      urlToLoad = 'https://$url';
    }
    _controller.loadRequest(Uri.parse(urlToLoad));
  }

  Future<void> _extractLinks() async {
    try {
      // Create a JavaScript snippet to extract links matching the prefixes
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

      final result = await _controller.runJavaScriptReturningResult(jsCode);

      // Parse the result
      String resultString = result.toString();
      // Remove surrounding quotes if present
      if (resultString.startsWith('"') && resultString.endsWith('"')) {
        resultString = resultString.substring(1, resultString.length - 1);
      }
      // Unescape JSON string
      resultString = resultString.replaceAll(r'\"', '"').replaceAll(r'\\', '\\');

      final List<dynamic> hrefs = json.decode(resultString);

      // Print each href on stdout
      for (var href in hrefs) {
        stdout.writeln(href);
      }
    } catch (e) {
      stderr.writeln('Error extracting links: $e');
    }
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Address bar
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.grey[200],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (await _controller.canGoBack()) {
                      _controller.goBack();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () async {
                    if (await _controller.canGoForward()) {
                      _controller.goForward();
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    _controller.reload();
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      hintText: 'Enter URL',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: _loadUrl,
                  ),
                ),
                const SizedBox(width: 8),
                // Site selector dropdown
                if (_sites.isNotEmpty)
                  SizedBox(
                    width: 120,
                    child: DropdownButton<String>(
                      value: _selectedSite,
                      hint: const Text('Site'),
                      isExpanded: true,
                      items: _sites.entries.map((entry) {
                        return DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.key),
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
            child: WebViewWidget(controller: _controller),
          ),
          // Bottom toolbar
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              border: Border(
                top: BorderSide(color: Colors.grey[400]!),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Extract button
                ElevatedButton(
                  onPressed: _extractLinks,
                  child: const Text('Extract'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
