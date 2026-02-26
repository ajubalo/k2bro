/// Shared utility functions used by both main.dart and tree.dart.

/// Check if a URL is a K2S file URL.
bool isK2sFileUrl(String url) {
  return RegExp(r'https?://(k2s\.cc|keep2share\.cc)/file/').hasMatch(url);
}

/// Extract the 13-char file ID from a K2S URL.
String? extractFileId(String url) {
  final match = RegExp(r'https?://(k2s\.cc|keep2share\.cc)/file/([^/?]+)').firstMatch(url);
  return match?.group(2);
}

/// Extract display label for a K2S link (filename portion after the file ID).
String linkLabel(String url) {
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

/// Build a navigable URL from a stored domain key and optional path.
/// Domain keys starting with "http://" use HTTP; otherwise HTTPS.
String domainBaseUrl(String domain) {
  if (domain.startsWith('http://')) return domain;
  return 'https://$domain';
}

/// Extract the display label for a domain (strip protocol prefix if stored).
String domainLabel(String domain) {
  if (domain.startsWith('http://')) return domain.substring(7);
  return domain;
}

/// Format seconds as "m:ss".
String formatTime(int totalSeconds) {
  final mm = totalSeconds ~/ 60;
  final ss = totalSeconds % 60;
  return '$mm:${ss.toString().padLeft(2, '0')}';
}

/// Format bytes as "1.2G" or "123M".
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}G';
  }
  return '${(bytes / (1024 * 1024)).round()}M';
}

/// Compare two strings with natural number sort (ascending) for trailing numbers.
int compareByTrailingNumber(String a, String b) {
  final numPattern = RegExp(r'(\d+)(?!.*\d)');
  final matchA = numPattern.firstMatch(a);
  final matchB = numPattern.firstMatch(b);
  if (matchA == null && matchB == null) return a.compareTo(b);
  final prefixA = a.replaceFirst(numPattern, '');
  final prefixB = b.replaceFirst(numPattern, '');
  if (prefixA != prefixB) return a.compareTo(b);
  if (matchA != null && matchB != null) {
    return int.parse(matchA.group(1)!).compareTo(int.parse(matchB.group(1)!));
  }
  return a.compareTo(b);
}

/// Compare with natural number sort (descending) for trailing numbers.
int compareByTrailingNumberDesc(String a, String b) {
  final numPattern = RegExp(r'(\d+)(?!.*\d)');
  final matchA = numPattern.firstMatch(a);
  final matchB = numPattern.firstMatch(b);
  if (matchA == null && matchB == null) return a.compareTo(b);
  final prefixA = a.replaceFirst(numPattern, '');
  final prefixB = b.replaceFirst(numPattern, '');
  if (prefixA != prefixB) return a.compareTo(b);
  if (matchA != null && matchB != null) {
    return int.parse(matchB.group(1)!).compareTo(int.parse(matchA.group(1)!));
  }
  return a.compareTo(b);
}

/// Group multi-part RAR links into RarGroup entries.
/// Returns a list of String (standalone link) or RarGroup (2+ parts).
List<Object> groupRarParts(List<String> links) {
  final partPattern = RegExp(r'^(.+?)\.part(\d+)\.rar$', caseSensitive: false);
  final buckets = <String, List<(String, int)>>{};
  final order = <String>[];

  for (final link in links) {
    final filename = linkLabel(link);
    final m = partPattern.firstMatch(filename);
    if (m != null) {
      final base = m.group(1)!;
      final partNum = int.parse(m.group(2)!);
      final key = base.toLowerCase();
      if (!buckets.containsKey(key)) {
        buckets[key] = [];
        order.add(key);
      }
      buckets[key]!.add((link, partNum));
    }
  }

  final groupedUrls = <String>{};
  final groups = <String, RarGroup>{};
  for (final key in order) {
    final bucket = buckets[key]!;
    if (bucket.length < 2) continue;
    bucket.sort((a, b) => a.$2.compareTo(b.$2));
    final sortedUrls = bucket.map((e) => e.$1).toList();
    final filename = linkLabel(sortedUrls.first);
    final m = partPattern.firstMatch(filename)!;
    final displayBase = '${m.group(1)!}.rar';
    groups[key] = RarGroup(
      baseName: displayBase,
      parts: sortedUrls,
      representative: sortedUrls.first,
    );
    groupedUrls.addAll(sortedUrls);
  }

  final result = <Object>[];
  final emittedGroupKeys = <String>{};
  for (final link in links) {
    if (!groupedUrls.contains(link)) {
      result.add(link);
    } else {
      final filename = linkLabel(link);
      final m = partPattern.firstMatch(filename)!;
      final key = m.group(1)!.toLowerCase();
      if (!emittedGroupKeys.contains(key)) {
        result.add(groups[key]!);
        emittedGroupKeys.add(key);
      }
    }
  }
  return result;
}

/// RAR part group (view-only, not persisted).
class RarGroup {
  final String baseName;       // e.g. "video.rar"
  final List<String> parts;    // all part URLs, sorted by part number
  final String representative; // parts.first — used for play/preview/selection

  const RarGroup({
    required this.baseName,
    required this.parts,
    required this.representative,
  });
}
