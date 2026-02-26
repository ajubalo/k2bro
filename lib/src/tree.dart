import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../main.dart';
import 'utils.dart';

// ============================================================
// Public utility functions (used by both TreeView and main.dart HTTP server)
// ============================================================

/// Classify all links in AppData into fresh/freshVr/tagged/taggedVr categories.
Map<String, Map<String, Map<String, List<String>>>> classifyLinks(AppData appData) {
  final result = <String, Map<String, Map<String, List<String>>>>{
    'fresh': {},
    'freshVr': {},
    'tagged': {},
    'taggedVr': {},
  };
  for (final domain in appData.domains) {
    final paths = appData.pathsFor(domain);
    if (paths.isEmpty) {
      result['fresh']!.putIfAbsent(domain, () => {});
      continue;
    }
    for (final path in paths) {
      final visibleLinks = appData.visibleLinksFor(domain, path);
      if (visibleLinks.isEmpty) {
        result['fresh']!.putIfAbsent(domain, () => {});
        result['fresh']![domain]!.putIfAbsent(path, () => []);
        continue;
      }
      for (final link in visibleLinks) {
        final tags = appData.getTags(domain, path, link);
        final isVr = appData.getVr(domain, path, link);
        String category;
        if (tags.isNotEmpty) {
          category = isVr ? 'taggedVr' : 'tagged';
        } else {
          category = isVr ? 'freshVr' : 'fresh';
        }
        result[category]!.putIfAbsent(domain, () => {});
        result[category]![domain]!.putIfAbsent(path, () => []);
        result[category]![domain]![path]!.add(link);
      }
    }
  }
  return result;
}

/// Group sorted paths by common prefix into prefix groups.
List<({String? prefix, List<String> paths})> groupPathsByPrefix(List<String> sortedPaths) {
  if (sortedPaths.length <= 1) {
    return sortedPaths.map((p) => (prefix: null as String?, paths: [p])).toList();
  }
  final groups = <({String? prefix, List<String> paths})>[];
  int i = 0;
  while (i < sortedPaths.length) {
    final current = sortedPaths[i];
    final children = <String>[current];
    int j = i + 1;
    while (j < sortedPaths.length && sortedPaths[j].startsWith(current)) {
      children.add(sortedPaths[j]);
      j++;
    }
    if (children.length > 1) {
      groups.add((prefix: current, paths: children));
    } else {
      groups.add((prefix: null, paths: [current]));
    }
    i = j;
  }
  return groups;
}

// ============================================================
// Tree selection value class
// ============================================================
class TreeSelection {
  final String? domain;
  final String? path;
  final String? link;
  final List<String>? groupPaths;
  final int? searchIndex;
  /// The category key of the selected node (e.g. 'fresh', 'freshVr', 'tagged\t2', 'taggedVr\t1').
  final String? category;

  const TreeSelection({this.domain, this.path, this.link, this.groupPaths, this.searchIndex, this.category});

  bool get isVrCategory {
    if (category == null) return false;
    return category == 'freshVr' || category!.startsWith('taggedVr');
  }
}

// ============================================================
// Global overlay state — set from _MainPageState.didChangeDependencies
// ============================================================
OverlayState? globalOverlay;

// ============================================================
// Global registry to close all sprite hover overlays
// ============================================================
final Set<OverlayEntry> _activeSpriteOverlays = {};

void closeAllSpriteHovers() {
  final entries = _activeSpriteOverlays.toList();
  _activeSpriteOverlays.clear();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    for (final entry in entries) {
      try {
        if (entry.mounted) entry.remove();
      } catch (_) {}
    }
  });
}

// ============================================================
// TreeView Widget
// ============================================================
class TreeView extends StatefulWidget {
  final AppData appData;
  final List<RecentVideo> recentVideos;
  final int selectedPlayer;
  final List<Player> players;
  final String? currentPreviewK2sUrl;
  final String? playableK2sUrl;

  // Extract loop state (owned by parent)
  final bool deepExtract;
  final bool extractLooping;
  final int extractLoopPage;
  final TextEditingController extractLimitController;

  // Search results (shared list, mutated by tree, persisted by parent)
  final List<(String, List<(String, String, String)>)> searchResults;

  // Callbacks
  final void Function(String url) onLoadUrl;
  final void Function(String url) onPreviewLink;
  final VoidCallback onAddSite;
  final VoidCallback onAddSiteWithDialog;
  final VoidCallback onExtractLinks;
  final VoidCallback onStartExtractLoop;
  final VoidCallback onRemoveSelected;
  final VoidCallback onRemoveBySubstring;
  final VoidCallback onDedupSelected;
  final VoidCallback onVrSelected;
  final VoidCallback onPlayK2sUrl;
  final void Function(bool) onDeepExtractChanged;
  final void Function(int playerIdx, RecentVideo video) onSwitchVideo;
  final VoidCallback onSaveData;
  final VoidCallback onSaveRecent;
  final VoidCallback onSaveSearches;
  final void Function(TreeSelection selection) onSelectionChanged;
  final VoidCallback onExtractLoopStop;

  // Info data
  final Map<String, Map<String, String>> infoData;
  final void Function(String path, {String? folder}) onInfoPreview;
  final void Function(String path, String name, {String? folder}) onInfoPlay;

  const TreeView({
    super.key,
    required this.appData,
    required this.recentVideos,
    required this.selectedPlayer,
    required this.players,
    required this.currentPreviewK2sUrl,
    required this.playableK2sUrl,
    required this.deepExtract,
    required this.extractLooping,
    required this.extractLoopPage,
    required this.extractLimitController,
    required this.searchResults,
    required this.onLoadUrl,
    required this.onPreviewLink,
    required this.onAddSite,
    required this.onAddSiteWithDialog,
    required this.onExtractLinks,
    required this.onStartExtractLoop,
    required this.onRemoveSelected,
    required this.onRemoveBySubstring,
    required this.onDedupSelected,
    required this.onVrSelected,
    required this.onPlayK2sUrl,
    required this.onDeepExtractChanged,
    required this.onSwitchVideo,
    required this.onSaveData,
    required this.onSaveRecent,
    required this.onSaveSearches,
    required this.onSelectionChanged,
    required this.onExtractLoopStop,
    required this.infoData,
    required this.onInfoPreview,
    required this.onInfoPlay,
  });

  @override
  State<TreeView> createState() => TreeViewState();
}

class TreeViewState extends State<TreeView> {
  // Selection state
  String? _selectedDomain;
  String? _selectedPath;
  String? _selectedLink;
  List<String>? _selectedGroupPaths;
  int? _selectedSearchIndex;
  String? _selectedCategory;

  // Info selection state
  String? _selectedInfoFolder;
  String? _selectedInfoSizeKey;

  // Pick scope
  String? _pickScopeDomain;
  String? _pickScopePath;
  List<String>? _pickScopeGroupPaths;

  // Expand/collapse state
  final Set<String> _expandedCategories = {};
  final Set<String> _expandedCategoryRatings = {};
  final Set<String> _expandedDomains = {};
  final Set<String> _expandedPaths = {};
  final Set<String> _expandedGroups = {};
  final Set<int> _expandedSearches = {};
  final Set<String> _expandedInfoFolders = {};
  List<String>? _shuffledInfoFolders;
  final Map<String, List<MapEntry<String, String>>> _shuffledInfoEntries = {};
  GlobalKey _selectedTreeNodeKey = GlobalKey();

  TreeSelection get selection => TreeSelection(
    domain: _selectedDomain,
    path: _selectedPath,
    link: _selectedLink,
    groupPaths: _selectedGroupPaths,
    searchIndex: _selectedSearchIndex,
    category: _selectedCategory,
  );

  @override
  void dispose() {
    closeAllSpriteHovers();
    super.dispose();
  }

  void _notifySelectionChanged() {
    widget.onSelectionChanged(selection);
  }

  // -- Public methods callable via GlobalKey --

  /// Reset all tree UI state (selection, expansion, overlays).
  /// Called on hot reload to recover from stale state.
  void resetState() {
    closeAllSpriteHovers();
    setState(() {
      _selectedDomain = null;
      _selectedPath = null;
      _selectedLink = null;
      _selectedGroupPaths = null;
      _selectedSearchIndex = null;
      _selectedCategory = null;
      _selectedInfoFolder = null;
      _selectedInfoSizeKey = null;
      _pickScopeDomain = null;
      _pickScopePath = null;
      _pickScopeGroupPaths = null;
      _expandedCategories.clear();
      _expandedCategoryRatings.clear();
      _expandedDomains.clear();
      _expandedPaths.clear();
      _expandedGroups.clear();
      _expandedSearches.clear();
      _expandedInfoFolders.clear();
      _shuffledInfoFolders = null;
      _shuffledInfoEntries.clear();
      _selectedTreeNodeKey = GlobalKey();
    });
    _notifySelectionChanged();
  }

  void clearPickScope() {
    _pickScopeDomain = null;
    _pickScopePath = null;
    _pickScopeGroupPaths = null;
    _selectedSearchIndex = null;
    _notifySelectionChanged();
  }

  void selectLink(String domain, String path, String link) {
    final tags = widget.appData.getTags(domain, path, link);
    final isVr = widget.appData.getVr(domain, path, link);
    setState(() {
      _selectedDomain = domain;
      _selectedPath = path;
      _selectedLink = link;
      _selectedGroupPaths = null;
      _selectedCategory = tags.isNotEmpty
          ? (isVr ? 'taggedVr' : 'tagged')
          : (isVr ? 'freshVr' : 'fresh');
    });
    _notifySelectionChanged();
  }

  void navigateToLink(String domain, String path, String link) {
    setState(() {
      _selectedDomain = domain;
      _selectedPath = path;
      _selectedLink = link;
      _selectedGroupPaths = null;
      // Expand all ancestors
      // Find which category this link belongs to
      final tags = widget.appData.getTags(domain, path, link);
      final isVr = widget.appData.getVr(domain, path, link);
      String category;
      if (tags.isNotEmpty) {
        category = isVr ? 'taggedVr' : 'tagged';
      } else {
        category = isVr ? 'freshVr' : 'fresh';
      }
      _selectedCategory = category;
      _expandedCategories.add(category);
      // If tagged, expand the rating sub-group
      if (category == 'tagged' || category == 'taggedVr') {
        final rating = widget.appData.getRating(domain, path, link);
        if (rating != null) {
          _expandedCategoryRatings.add('$category\t$rating');
          _expandedDomains.add('$category\t$rating\t$domain');
        } else {
          _expandedDomains.add('$category\tunrated\t$domain');
        }
      } else {
        _expandedDomains.add('$category\t$domain');
      }
      _expandGroupForPath(domain, path);
      _expandedPaths.add('$domain\t$path');
    });
    _notifySelectionChanged();
    _scrollToSelectedNode();
  }

  // -- Collapse helpers --

  void _collapseCategory(String category) {
    _expandedCategories.remove(category);
    _expandedCategoryRatings.removeWhere((k) => k.startsWith('$category\t'));
    _expandedDomains.removeWhere((k) => k.startsWith('$category\t'));
  }

  void _collapseCategoryRating(String ratingKey) {
    _expandedCategoryRatings.remove(ratingKey);
    _expandedDomains.removeWhere((k) => k.startsWith('$ratingKey\t'));
  }

  void _collapseDomain(String domainKey) {
    _expandedDomains.remove(domainKey);
    final domain = domainKey.split('\t').last;
    _expandedPaths.removeWhere((k) => k.startsWith('$domain\t'));
    _expandedGroups.removeWhere((k) => k.startsWith('$domain\t'));
  }

  void _collapseGroup(String groupKey) {
    _expandedGroups.remove(groupKey);
    final parts = groupKey.split('\t');
    if (parts.length >= 2) {
      final domain = parts[0];
      final prefix = parts[1];
      _expandedPaths.removeWhere((k) => k.startsWith('$domain\t$prefix'));
    }
  }

  void _scrollToSelectedNode() {
    // Create a fresh GlobalKey so the previous one is released and not
    // reused across different widget types (which causes element-tracking
    // assertion failures).
    _selectedTreeNodeKey = GlobalKey();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _selectedTreeNodeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.3);
      }
    });
  }

  void _clearPickScope() {
    _pickScopeDomain = null;
    _pickScopePath = null;
    _pickScopeGroupPaths = null;
    _selectedInfoFolder = null;
    _selectedInfoSizeKey = null;
    _selectedSearchIndex = null;
  }

  // -- Classification & grouping helpers --

  Map<String, Map<String, Map<String, List<String>>>> _classifyLinks() =>
      classifyLinks(widget.appData);

  int _countLinks(Map<String, Map<String, List<String>>> catMap) {
    int count = 0;
    for (final paths in catMap.values) {
      for (final links in paths.values) {
        count += links.length;
      }
    }
    return count;
  }

  void _expandGroupForPath(String domain, String path) {
    final allPaths = widget.appData.pathsFor(domain)..sort(compareByTrailingNumber);
    for (final p in allPaths) {
      if (p != path && path.startsWith(p)) {
        _expandedGroups.add('$domain\t$p');
        return;
      }
      if (p == path) {
        final idx = allPaths.indexOf(p);
        if (idx + 1 < allPaths.length && allPaths[idx + 1].startsWith(path)) {
          _expandedGroups.add('$domain\t$path');
        }
        return;
      }
    }
  }

  List<({String? prefix, List<String> paths})> _groupPathsByPrefix(List<String> sortedPaths) =>
      groupPathsByPrefix(sortedPaths);

  int? _bestGroupRating(String domain, List<String> paths) {
    int? best;
    for (final p in paths) {
      final r = widget.appData.getPathRating(domain, p);
      if (r != null && (best == null || r < best)) best = r;
    }
    return best;
  }

  // -- Search --

  void _showSearchDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search links'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Regular expression (case insensitive)',
          ),
          onSubmitted: (_) {
            Navigator.of(ctx).pop(controller.text);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    ).then((value) {
      if (value == null || (value as String).trim().isEmpty) return;
      _performSearch(value.trim());
    });
  }

  void _performSearch(String pattern) {
    final RegExp regexp;
    try {
      regexp = RegExp(pattern, caseSensitive: false);
    } catch (_) {
      return;
    }

    final matches = <(String, String, String)>[];

    if (_selectedDomain != null && _selectedPath != null) {
      _searchInPath(_selectedDomain!, _selectedPath!, regexp, matches);
    } else if (_selectedDomain != null && _selectedGroupPaths != null) {
      for (final path in _selectedGroupPaths!) {
        _searchInPath(_selectedDomain!, path, regexp, matches);
      }
    } else if (_selectedDomain != null) {
      for (final path in widget.appData.pathsFor(_selectedDomain!)) {
        _searchInPath(_selectedDomain!, path, regexp, matches);
      }
    } else {
      for (final domain in widget.appData.domains) {
        for (final path in widget.appData.pathsFor(domain)) {
          _searchInPath(domain, path, regexp, matches);
        }
      }
    }

    if (matches.isEmpty) return;

    setState(() {
      widget.searchResults.add((pattern, matches));
      _expandedCategories.add('search');
      _expandedSearches.add(widget.searchResults.length - 1);
    });
    widget.onSaveSearches();
  }

  void _searchInPath(String domain, String path, RegExp regexp, List<(String, String, String)> matches) {
    for (final link in widget.appData.visibleLinksFor(domain, path)) {
      final name = linkLabel(link);
      if (regexp.hasMatch(name)) {
        matches.add((domain, path, link));
      }
    }
  }

  // -- Node building --

  Widget _buildRarGroupNode(String domain, String path, RarGroup group, int level, {String? categoryKey}) {
    final rep = group.representative;
    final isSelected = _selectedDomain == domain &&
        _selectedPath == path &&
        _selectedLink == rep;

    int? bestRating;
    for (final partUrl in group.parts) {
      final r = widget.appData.getRating(domain, path, partUrl);
      if (r != null && (bestRating == null || r < bestRating)) bestRating = r;
    }
    Color? ratingColor;
    if (bestRating != null && bestRating >= 1 && bestRating <= 5) {
      ratingColor = kRatingColors[bestRating - 1];
    }

    int? totalSize;
    for (final partUrl in group.parts) {
      final sz = widget.appData.getFileSize(domain, path, partUrl);
      if (sz != null) totalSize = (totalSize ?? 0) + sz;
    }
    final sizePrefix = totalSize != null ? '${formatFileSize(totalSize)} ' : '';

    final isVr = group.parts.any((p) => widget.appData.getVr(domain, path, p));
    final vrPrefix = isVr ? '\u{1F576}\u{FE0F} ' : '';

    final allTags = <Map<String, dynamic>>[];
    for (final partUrl in group.parts) {
      allTags.addAll(widget.appData.getTags(domain, path, partUrl));
    }
    final tagWidgets = <Widget>[];
    final repFileId = extractFileId(rep) ?? '';
    for (final tag in allTags) {
      final frame = tag['frame'] as int;
      final tagKey = tag['tag'] as String;
      final tagIdx = kTagKeys.indexOf(tagKey);
      final emoji = tagIdx >= 0 ? kTagEmojis[tagIdx] : '?';
      tagWidgets.add(
        SpriteHoverTag(
          emoji: emoji,
          frame: frame,
          fileId: repFileId,
          timeLabel: formatTime(frame * 10),
          fontSize: 12,
          onTap: () {
            final playerIdx = widget.selectedPlayer;
            final video = widget.recentVideos.where((v) => v.k2sUrl == rep).firstOrNull;
            if (video != null) {
              widget.onSwitchVideo(playerIdx, video);
              Future.delayed(const Duration(milliseconds: 800), () {
                widget.players[playerIdx].seek(Duration(milliseconds: frame * 10 * 1000));
              });
            }
            widget.onPreviewLink(rep);
          },
        ),
      );
    }

    return _TreeNode(
      level: level,
      icon: Icons.archive,
      label: '$vrPrefix$sizePrefix${group.baseName} (${group.parts.length} parts)',
      selected: isSelected,
      backgroundColor: ratingColor,
      tagWidgets: tagWidgets.isNotEmpty ? tagWidgets : null,
      onTap: () {
        _clearPickScope();
        setState(() {
          _selectedDomain = domain;
          _selectedPath = path;
          _selectedLink = rep;
          _selectedGroupPaths = null;
          _selectedCategory = categoryKey;
        });
        _notifySelectionChanged();
        widget.onPreviewLink(rep);
      },
      onSecondaryTap: () {
        setState(() {
          for (final partUrl in group.parts) {
            widget.appData.setHidden(domain, path, partUrl, true);
          }
        });
        widget.recentVideos.removeWhere((v) => group.parts.contains(v.k2sUrl));
        widget.onSaveData();
        widget.onSaveRecent();
      },
    );
  }

  Widget _buildLinkNode(String domain, String path, String link, int level, {String? categoryKey}) {
    final isLinkSelected = _selectedDomain == domain &&
        _selectedPath == path &&
        _selectedLink == link;
    final rating = widget.appData.getRating(domain, path, link);
    Color? ratingColor;
    if (rating != null && rating >= 1 && rating <= 5) {
      ratingColor = kRatingColors[rating - 1];
    }

    final linkTags = widget.appData.getTags(domain, path, link);
    final linkTagWidgets = <Widget>[];
    final linkFileId = extractFileId(link) ?? '';
    for (final tag in linkTags) {
      final frame = tag['frame'] as int;
      final tagKey = tag['tag'] as String;
      final tagIdx = kTagKeys.indexOf(tagKey);
      final emoji = tagIdx >= 0 ? kTagEmojis[tagIdx] : '?';
      linkTagWidgets.add(
        SpriteHoverTag(
          emoji: emoji,
          frame: frame,
          fileId: linkFileId,
          timeLabel: formatTime(frame * 10),
          fontSize: 12,
          onTap: () {
            final playerIdx = widget.selectedPlayer;
            final video = widget.recentVideos.where((v) => v.k2sUrl == link).firstOrNull;
            if (video != null) {
              widget.onSwitchVideo(playerIdx, video);
              Future.delayed(const Duration(milliseconds: 800), () {
                widget.players[playerIdx].seek(Duration(milliseconds: frame * 10 * 1000));
              });
            }
            widget.onPreviewLink(link);
          },
        ),
      );
    }

    final fileSize = widget.appData.getFileSize(domain, path, link);
    final sizePrefix = fileSize != null ? '${formatFileSize(fileSize)} ' : '';
    final isVr = widget.appData.getVr(domain, path, link);
    final vrPrefix = isVr ? '\u{1F576}\u{FE0F} ' : '';

    return _TreeNode(
      level: level,
      icon: Icons.link,
      label: '$vrPrefix$sizePrefix${linkLabel(link)}',
      selected: isLinkSelected,
      backgroundColor: ratingColor,
      tagWidgets: linkTagWidgets.isNotEmpty ? linkTagWidgets : null,
      onTap: () {
        _clearPickScope();
        setState(() {
          _selectedDomain = domain;
          _selectedPath = path;
          _selectedLink = link;
          _selectedGroupPaths = null;
          _selectedCategory = categoryKey;
        });
        _notifySelectionChanged();
        widget.onPreviewLink(link);
      },
      onSecondaryTap: () {
        setState(() {
          widget.appData.setHidden(domain, path, link, true);
        });
        widget.recentVideos.removeWhere((v) => v.k2sUrl == link);
        widget.onSaveData();
        widget.onSaveRecent();
      },
    );
  }

  void _buildPathNode(List<Widget> nodes, String domain, String path, List<String> links, int level, {String? categoryKey}) {
    final pathKey = '$domain\t$path';
    final isPathExpanded = _expandedPaths.contains(pathKey);
    final isPathSelected = _selectedDomain == domain && _selectedPath == path && _selectedLink == null;
    final isPathPickScope = _pickScopeDomain != null
        ? (_pickScopeDomain == domain && _pickScopePath == path)
        : (_selectedDomain == domain && _selectedPath == path);
    final pathRating = widget.appData.getPathRating(domain, path);
    Color? pathBgColor;
    if (pathRating != null && pathRating >= 1 && pathRating <= 5) {
      pathBgColor = kRatingColors[pathRating - 1];
    }

    nodes.add(
      _TreeNode(
        key: isPathSelected ? _selectedTreeNodeKey : null,
        level: level,
        icon: Icons.folder,
        label: '$path (${links.length})',
        selected: isPathSelected,
        pickScope: isPathPickScope,
        backgroundColor: pathBgColor,
        expanded: isPathExpanded,
        onToggle: () {
          setState(() {
            if (isPathExpanded) _expandedPaths.remove(pathKey);
            else _expandedPaths.add(pathKey);
          });
        },
        onTap: () {
          _clearPickScope();
          setState(() {
            _selectedDomain = domain;
            _selectedPath = path;
            _selectedLink = null;
            _selectedGroupPaths = null;
            _selectedCategory = categoryKey;
            _expandedPaths.add(pathKey);
          });
          _notifySelectionChanged();
          widget.onLoadUrl('${domainBaseUrl(domain)}$path');
          _scrollToSelectedNode();
        },
      ),
    );

    if (!isPathExpanded) return;

    final sortedLinks = links.toList()..sort();
    final grouped = groupRarParts(sortedLinks);
    for (final item in grouped) {
      if (item is RarGroup) {
        nodes.add(_buildRarGroupNode(domain, path, item, level + 1, categoryKey: categoryKey));
      } else {
        nodes.add(_buildLinkNode(domain, path, item as String, level + 1, categoryKey: categoryKey));
      }
    }
  }

  void _buildDomainPathLinks(List<Widget> nodes, String categoryKey, Map<String, Map<String, List<String>>> catMap, int baseLevel) {
    final sortedDomains = catMap.keys.toList()..sort();
    for (final domain in sortedDomains) {
      final paths = catMap[domain]!;
      final domainKey = '$categoryKey\t$domain';
      final isDomainExpanded = _expandedDomains.contains(domainKey);
      final isDomainSelected = _selectedDomain == domain && _selectedPath == null && _selectedLink == null && _selectedGroupPaths == null;

      final isDomainPickScope = _pickScopeDomain != null
          ? (_pickScopeDomain == domain && _pickScopePath == null && _pickScopeGroupPaths == null)
          : (_selectedDomain == domain && _selectedPath == null && _selectedGroupPaths == null);
      nodes.add(
        _TreeNode(
          key: isDomainSelected ? _selectedTreeNodeKey : null,
          level: baseLevel,
          icon: Icons.language,
          label: '${domainLabel(domain)} (${paths.values.fold<int>(0, (sum, l) => sum + l.length)})',
          selected: isDomainSelected,
          pickScope: isDomainPickScope,
          expanded: isDomainExpanded,
          onToggle: () {
            setState(() {
              if (isDomainExpanded) _collapseDomain(domainKey);
              else _expandedDomains.add(domainKey);
            });
          },
          onTap: () {
            _clearPickScope();
            setState(() {
              _selectedDomain = domain;
              _selectedPath = null;
              _selectedLink = null;
              _selectedGroupPaths = null;
              _selectedCategory = categoryKey;
              _expandedDomains.add(domainKey);
            });
            _notifySelectionChanged();
            widget.onLoadUrl(domainBaseUrl(domain));
            _scrollToSelectedNode();
          },
        ),
      );

      if (!isDomainExpanded) continue;

      final alphaSorted = paths.keys.toList()..sort(compareByTrailingNumber);
      final groups = _groupPathsByPrefix(alphaSorted);

      groups.sort((a, b) {
        final bestA = _bestGroupRating(domain, a.paths);
        final bestB = _bestGroupRating(domain, b.paths);
        if (bestA != null && bestB != null) {
          final cmp = bestA.compareTo(bestB);
          if (cmp != 0) return cmp;
        }
        if (bestA != null) return -1;
        if (bestB != null) return 1;
        final nameA = a.prefix ?? a.paths.first;
        final nameB = b.prefix ?? b.paths.first;
        return compareByTrailingNumberDesc(nameA, nameB);
      });

      for (final group in groups) {
        if (group.prefix != null) {
          final groupPrefix = group.prefix!;
          final groupKey = '$domain\t$groupPrefix';
          final isGroupExpanded = _expandedGroups.contains(groupKey);
          final groupLinkCount = group.paths.fold<int>(0, (sum, p) => sum + (paths[p]?.length ?? 0));
          final bestRating = _bestGroupRating(domain, group.paths);
          Color? groupBgColor;
          if (bestRating != null && bestRating >= 1 && bestRating <= 5) {
            groupBgColor = kRatingColors[bestRating - 1];
          }

          final isGroupSelected = _selectedDomain == domain && _selectedPath == null && _selectedLink == null
              && _selectedGroupPaths != null && _selectedGroupPaths!.length == group.paths.length
              && _selectedGroupPaths!.first == group.paths.first;
          final isGroupPickScope = _pickScopeGroupPaths != null
              && _pickScopeDomain == domain
              && _pickScopeGroupPaths!.length == group.paths.length
              && _pickScopeGroupPaths!.first == group.paths.first;

          nodes.add(
            _TreeNode(
              key: isGroupSelected ? _selectedTreeNodeKey : null,
              level: baseLevel + 1,
              icon: Icons.folder_special,
              label: '$groupPrefix ($groupLinkCount)',
              selected: isGroupSelected,
              pickScope: isGroupPickScope,
              backgroundColor: groupBgColor,
              expanded: isGroupExpanded,
              onToggle: () {
                setState(() {
                  if (isGroupExpanded) _collapseGroup(groupKey);
                  else _expandedGroups.add(groupKey);
                });
              },
              onTap: () {
                _clearPickScope();
                setState(() {
                  _selectedDomain = domain;
                  _selectedPath = null;
                  _selectedLink = null;
                  _selectedGroupPaths = List.from(group.paths);
                  _selectedCategory = categoryKey;
                  _expandedGroups.add(groupKey);
                });
                _notifySelectionChanged();
                _scrollToSelectedNode();
              },
            ),
          );

          if (!isGroupExpanded) continue;

          final sortedChildren = group.paths.toList()..sort((a, b) {
            final ra = widget.appData.getPathRating(domain, a);
            final rb = widget.appData.getPathRating(domain, b);
            if (ra != null && rb != null) {
              final cmp = ra.compareTo(rb);
              if (cmp != 0) return cmp;
              return compareByTrailingNumberDesc(a, b);
            }
            if (ra != null) return -1;
            if (rb != null) return 1;
            return compareByTrailingNumberDesc(a, b);
          });
          for (final path in sortedChildren) {
            _buildPathNode(nodes, domain, path, paths[path]!, baseLevel + 2, categoryKey: categoryKey);
          }
        } else {
          final path = group.paths.first;
          _buildPathNode(nodes, domain, path, paths[path]!, baseLevel + 1, categoryKey: categoryKey);
        }
      }
    }
  }

  /// Build a tagged category (Tagged or Tagged VR) with rating sub-groups.
  void _buildTaggedCategory(
    List<Widget> nodes,
    String categoryKey,
    Map<String, Map<String, List<String>>> catMap,
    String label,
    IconData icon,
  ) {
    final count = _countLinks(catMap);
    if (count == 0 && categoryKey != 'tagged') return;

    final isExpanded = _expandedCategories.contains(categoryKey);
    nodes.add(
      _TreeNode(
        level: 0,
        icon: icon,
        label: '$label ($count)',
        selected: false,
        expanded: isExpanded,
        onToggle: () {
          setState(() {
            if (isExpanded) _collapseCategory(categoryKey);
            else _expandedCategories.add(categoryKey);
          });
        },
        onTap: () {
          setState(() {
            if (isExpanded) _collapseCategory(categoryKey);
            else _expandedCategories.add(categoryKey);
          });
        },
      ),
    );
    if (!isExpanded) return;

    // Sub-group by rating (1=Super, 2=Top, 3=Ok, 4=Uhm)
    for (int r = 1; r <= 4; r++) {
      final ratingMap = <String, Map<String, List<String>>>{};
      for (final domain in catMap.keys) {
        for (final path in catMap[domain]!.keys) {
          final links = catMap[domain]![path]!.where((l) => widget.appData.getRating(domain, path, l) == r).toList();
          if (links.isNotEmpty) {
            ratingMap.putIfAbsent(domain, () => {});
            ratingMap[domain]![path] = links;
          }
        }
      }
      if (ratingMap.isEmpty) continue;
      final ratingCount = _countLinks(ratingMap);
      final ratingKey = '$categoryKey\t$r';
      final isRatingExpanded = _expandedCategoryRatings.contains(ratingKey);
      nodes.add(
        _TreeNode(
          level: 1,
          icon: Icons.circle,
          label: '${kRatingLabels[r - 1]} ($ratingCount)',
          selected: false,
          backgroundColor: kRatingColors[r - 1],
          expanded: isRatingExpanded,
          onToggle: () {
            setState(() {
              if (isRatingExpanded) _collapseCategoryRating(ratingKey);
              else _expandedCategoryRatings.add(ratingKey);
            });
          },
          onTap: () {
            setState(() {
              if (isRatingExpanded) _collapseCategoryRating(ratingKey);
              else _expandedCategoryRatings.add(ratingKey);
            });
          },
        ),
      );
      if (isRatingExpanded) {
        _buildDomainPathLinks(nodes, ratingKey, ratingMap, 2);
      }
    }
    // Unrated tagged links
    final unratedMap = <String, Map<String, List<String>>>{};
    for (final domain in catMap.keys) {
      for (final path in catMap[domain]!.keys) {
        final links = catMap[domain]![path]!.where((l) => widget.appData.getRating(domain, path, l) == null).toList();
        if (links.isNotEmpty) {
          unratedMap.putIfAbsent(domain, () => {});
          unratedMap[domain]![path] = links;
        }
      }
    }
    if (unratedMap.isNotEmpty) {
      _buildDomainPathLinks(nodes, '$categoryKey\tunrated', unratedMap, 1);
    }
  }

  /// Build search results for a VR filter (non-VR or VR).
  void _buildSearchCategory(List<Widget> nodes, String categoryKey, String label, IconData icon, bool vrFilter) {
    final filteredResults = <(String, List<(String, String, String)>)>[];
    for (final (pattern, matches) in widget.searchResults) {
      final filtered = matches.where((m) => widget.appData.getVr(m.$1, m.$2, m.$3) == vrFilter).toList();
      if (filtered.isNotEmpty) {
        filteredResults.add((pattern, filtered));
      }
    }
    if (filteredResults.isEmpty) return;

    final totalMatches = filteredResults.fold<int>(0, (sum, s) => sum + s.$2.length);
    final isExpanded = _expandedCategories.contains(categoryKey);
    nodes.add(
      _TreeNode(
        level: 0,
        icon: icon,
        label: '$label ($totalMatches)',
        selected: false,
        expanded: isExpanded,
        onToggle: () {
          setState(() {
            if (isExpanded) {
              _expandedCategories.remove(categoryKey);
              if (categoryKey == 'search') _expandedSearches.clear();
            } else {
              _expandedCategories.add(categoryKey);
            }
          });
        },
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedCategories.remove(categoryKey);
              if (categoryKey == 'search') _expandedSearches.clear();
            } else {
              _expandedCategories.add(categoryKey);
            }
          });
        },
      ),
    );
    if (!isExpanded) return;

    if (categoryKey == 'search') {
      // Non-VR search: full interaction (expand, select, right-click remove)
      for (int si = 0; si < widget.searchResults.length; si++) {
        final (pattern, matches) = widget.searchResults[si];
        final nonVrMatches = matches.where((m) => !widget.appData.getVr(m.$1, m.$2, m.$3)).toList();
        if (nonVrMatches.isEmpty) continue;
        final isSubExpanded = _expandedSearches.contains(si);
        final isSelected = _selectedSearchIndex == si;
        nodes.add(
          _TreeNode(
            level: 1,
            icon: Icons.folder_special,
            label: '$pattern (${nonVrMatches.length})',
            selected: isSelected,
            expanded: isSubExpanded,
            onToggle: () {
              setState(() {
                if (isSubExpanded) _expandedSearches.remove(si);
                else _expandedSearches.add(si);
              });
            },
            onTap: () {
              setState(() {
                _selectedSearchIndex = si;
                _selectedDomain = null;
                _selectedPath = null;
                _selectedLink = null;
                _selectedGroupPaths = null;
                _selectedCategory = 'search';
                if (!isSubExpanded) _expandedSearches.add(si);
              });
              _notifySelectionChanged();
            },
            onSecondaryTap: () {
              setState(() {
                widget.searchResults.removeAt(si);
                _expandedSearches.remove(si);
                if (_selectedSearchIndex == si) _selectedSearchIndex = null;
                else if (_selectedSearchIndex != null && _selectedSearchIndex! > si) _selectedSearchIndex = _selectedSearchIndex! - 1;
                final adjusted = <int>{};
                for (final idx in _expandedSearches) {
                  if (idx > si) adjusted.add(idx - 1);
                  else adjusted.add(idx);
                }
                _expandedSearches.clear();
                _expandedSearches.addAll(adjusted);
              });
              _notifySelectionChanged();
              widget.onSaveSearches();
            },
          ),
        );
        if (isSubExpanded) {
          for (final (domain, path, link) in nonVrMatches) {
            nodes.add(_buildLinkNode(domain, path, link, 2, categoryKey: 'search'));
          }
        }
      }
    } else {
      // VR search: simple display
      for (final (pattern, vrMatches) in filteredResults) {
        nodes.add(
          _TreeNode(
            level: 1,
            icon: Icons.folder_special,
            label: '$pattern (${vrMatches.length})',
            selected: false,
            expanded: true,
            onToggle: () {},
            onTap: () {},
          ),
        );
        for (final (domain, path, link) in vrMatches) {
          nodes.add(_buildLinkNode(domain, path, link, 2, categoryKey: 'searchVr'));
        }
      }
    }
  }

  void _buildInfoNodes(List<Widget> nodes) {
    final folders = _shuffledInfoFolders ?? widget.infoData.keys.toList();
    for (final folder in folders) {
      final entries = widget.infoData[folder];
      if (entries == null) continue;
      final isFolderExpanded = _expandedInfoFolders.contains(folder);
      final isFolderSelected = _selectedInfoFolder == folder
          && _selectedInfoSizeKey == null;

      nodes.add(
        _TreeNode(
          level: 0,
          icon: Icons.folder,
          label: '$folder (${entries.length})',
          selected: isFolderSelected,
          expanded: isFolderExpanded,
          onToggle: () {
            setState(() {
              if (isFolderExpanded) {
                _expandedInfoFolders.remove(folder);
                _shuffledInfoEntries.remove(folder);
              } else {
                _expandedInfoFolders.add(folder);
                _shuffledInfoEntries[folder] = entries.entries.toList()..shuffle(Random());
              }
            });
          },
          onTap: () {
            _clearPickScope();
            setState(() {
              _selectedInfoFolder = folder;
              _selectedInfoSizeKey = null;
              _selectedDomain = folder;
              _selectedPath = 'info';
              _selectedLink = null;
              _selectedGroupPaths = null;
              _selectedCategory = 'info';
              if (!isFolderExpanded) {
                _expandedInfoFolders.add(folder);
                _shuffledInfoEntries[folder] = entries.entries.toList()..shuffle(Random());
              }
            });
            _notifySelectionChanged();
          },
        ),
      );

      if (!isFolderExpanded) continue;

      final shuffledEntries = _shuffledInfoEntries[folder] ?? entries.entries.toList();

      for (final entry in shuffledEntries) {
        final sizeKey = entry.key;
        final path = entry.value;
        final name = path.split('/').last;
        final isLinkSelected = _selectedInfoFolder == folder
            && _selectedInfoSizeKey == sizeKey;

        final sizeBytes = int.tryParse(sizeKey);
        final sizeLabel = sizeBytes != null ? formatFileSize(sizeBytes) : sizeKey;

        nodes.add(
          _TreeNode(
            level: 1,
            icon: Icons.video_file,
            label: '$sizeLabel $name',
            selected: isLinkSelected,
            onTap: () {
              _clearPickScope();
              setState(() {
                _selectedInfoFolder = folder;
                _selectedInfoSizeKey = sizeKey;
                _selectedDomain = folder;
                _selectedPath = 'info';
                _selectedLink = null;
                _selectedGroupPaths = null;
                _selectedCategory = 'info';
              });
              _notifySelectionChanged();
              widget.onInfoPreview(path, folder: folder);
            },
          ),
        );
      }
    }
  }

  List<Widget> _buildTreeNodes() {
    final classified = _classifyLinks();
    final nodes = <Widget>[];

    // Fresh
    final freshMap = classified['fresh']!;
    final freshCount = _countLinks(freshMap);
    final isFreshExpanded = _expandedCategories.contains('fresh');
    nodes.add(
      _TreeNode(
        level: 0,
        icon: Icons.fiber_new,
        label: 'Fresh ($freshCount)',
        selected: false,
        expanded: isFreshExpanded,
        onToggle: () {
          setState(() {
            if (isFreshExpanded) _collapseCategory('fresh');
            else _expandedCategories.add('fresh');
          });
        },
        onTap: () {
          setState(() {
            if (isFreshExpanded) _collapseCategory('fresh');
            else _expandedCategories.add('fresh');
          });
        },
      ),
    );
    if (isFreshExpanded) {
      _buildDomainPathLinks(nodes, 'fresh', freshMap, 1);
    }

    // Fresh VR
    final freshVrMap = classified['freshVr']!;
    final freshVrCount = _countLinks(freshVrMap);
    if (freshVrCount > 0) {
      final isFreshVrExpanded = _expandedCategories.contains('freshVr');
      nodes.add(
        _TreeNode(
          level: 0,
          icon: Icons.vrpano,
          label: 'Fresh VR ($freshVrCount)',
          selected: false,
          expanded: isFreshVrExpanded,
          onToggle: () {
            setState(() {
              if (isFreshVrExpanded) _collapseCategory('freshVr');
              else _expandedCategories.add('freshVr');
            });
          },
          onTap: () {
            setState(() {
              if (isFreshVrExpanded) _collapseCategory('freshVr');
              else _expandedCategories.add('freshVr');
            });
          },
        ),
      );
      if (isFreshVrExpanded) {
        _buildDomainPathLinks(nodes, 'freshVr', freshVrMap, 1);
      }
    }

    // Tagged
    _buildTaggedCategory(nodes, 'tagged', classified['tagged']!, 'Tagged', Icons.label);

    // Tagged VR
    final taggedVrMap = classified['taggedVr']!;
    final taggedVrCount = _countLinks(taggedVrMap);
    if (taggedVrCount > 0) {
      _buildTaggedCategory(nodes, 'taggedVr', taggedVrMap, 'Tagged VR', Icons.vrpano);
    }

    // Search (non-VR)
    if (widget.searchResults.isNotEmpty) {
      _buildSearchCategory(nodes, 'search', 'Search', Icons.search, false);
    }

    // Search VR
    if (widget.searchResults.isNotEmpty) {
      _buildSearchCategory(nodes, 'searchVr', 'Search VR', Icons.vrpano, true);
    }

    // Info folders (shown directly at top level)
    if (widget.infoData.isNotEmpty) {
      _buildInfoNodes(nodes);
    }

    return nodes;
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Expanded(
            child: widget.appData.domains.isEmpty && widget.infoData.isEmpty
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onSecondaryTap: widget.onAddSiteWithDialog,
                    child: ElevatedButton.icon(
                      onPressed: widget.onAddSite,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    height: 28,
                    child: TextField(
                      controller: widget.extractLimitController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 28,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: widget.deepExtract,
                          onChanged: (v) => widget.onDeepExtractChanged(v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        const Text('Deep', style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onSecondaryTap: widget.onStartExtractLoop,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (widget.extractLooping) {
                          widget.onExtractLoopStop();
                        } else {
                          widget.onExtractLinks();
                        }
                      },
                      icon: Icon(widget.extractLooping ? Icons.stop : Icons.link, size: 16),
                      label: Text(
                        widget.extractLooping ? 'Extract #${widget.extractLoopPage}' : 'Extract',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        backgroundColor: widget.extractLooping ? Colors.orange[100] : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onSecondaryTap: (_selectedDomain != null) ? widget.onRemoveBySubstring : null,
                    child: ElevatedButton.icon(
                      onPressed: (_selectedDomain != null) ? widget.onRemoveSelected : null,
                      icon: const Icon(Icons.delete, size: 16),
                      label: const Text('Remove', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        backgroundColor: Colors.red[100],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: widget.playableK2sUrl != null
                        ? widget.onPlayK2sUrl
                        : (_selectedCategory == 'info' && _selectedInfoSizeKey != null)
                            ? () {
                                final path = widget.infoData[_selectedInfoFolder]?[_selectedInfoSizeKey!];
                                if (path != null) {
                                  final name = path.split('/').last;
                                  widget.onInfoPlay(path, name, folder: _selectedInfoFolder);
                                }
                              }
                            : null,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Play', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedLink != null ? () {
                      widget.onLoadUrl(_selectedLink!);
                    } : null,
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: const Text('View', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedDomain != null ? widget.onDedupSelected : null,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Dedup', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _selectedDomain != null ? widget.onVrSelected : null,
                    icon: const Icon(Icons.vrpano, size: 16),
                    label: const Text('VR', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _showSearchDialog,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Search', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Sprite Hover Tag Widget
// ============================================================
class SpriteHoverTag extends StatefulWidget {
  final String emoji;
  final int frame;
  final String fileId;
  final String timeLabel;
  final double fontSize;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;

  const SpriteHoverTag({
    required this.emoji,
    required this.frame,
    required this.fileId,
    required this.timeLabel,
    this.fontSize = 16,
    this.onTap,
    this.onSecondaryTap,
  });

  @override
  State<SpriteHoverTag> createState() => _SpriteHoverTagState();
}

class _SpriteHoverTagState extends State<SpriteHoverTag> {
  OverlayEntry? _overlayEntry;
  Timer? _autoCloseTimer;
  bool _disposed = false;

  void _showSpriteOverlay(Offset globalPosition) {
    closeAllSpriteHovers();
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
    final overlay = globalOverlay;
    if (overlay == null) {
      _activeSpriteOverlays.remove(entry);
      _overlayEntry = null;
      return;
    }
    try {
      overlay.insert(entry);
    } catch (e) {
      stderr.writeln('[sprite-overlay] overlay.insert failed: $e');
      _activeSpriteOverlays.remove(entry);
      _overlayEntry = null;
      return;
    }

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (entry.mounted) entry.remove();
        } catch (_) {}
      });
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
// Tree Node Widget
// ============================================================
class _TreeNode extends StatelessWidget {
  final int level;
  final IconData icon;
  final String label;
  final bool selected;
  final bool? expanded;
  final VoidCallback onTap;
  final VoidCallback? onToggle;
  final VoidCallback? onSecondaryTap;
  final Color? backgroundColor;
  final List<Widget>? tagWidgets;
  final bool pickScope;

  const _TreeNode({
    super.key,
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
    this.pickScope = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onSecondaryTap: onSecondaryTap,
      child: Container(
        padding: EdgeInsets.only(left: 16.0 * level + 4, top: 3, bottom: 3, right: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.deepPurple.withOpacity(0.15)
              : backgroundColor?.withOpacity(0.2),
          border: pickScope ? Border.all(color: Colors.red, width: 1.5) : null,
        ),
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
