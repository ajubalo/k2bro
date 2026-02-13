# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

K2Bro is a macOS desktop app built with Flutter/Dart. It's a custom browser with dual video players for organizing and playing video content from Keep2Share (k2s.cc). The entire app lives in a single file: `lib/main.dart`.

## Development Commands

```bash
# Install dependencies
flutter pub get

# Run the app
flutter run

# Build release
flutter build macos

# Analyze code
flutter analyze
```

The Python utility (`util.py`) handles K2S API authentication and link resolution:
```bash
uv run util.py login       # Authenticate (always with captcha)
uv run util.py link <url>   # Resolve download URL
```

## Architecture

### Single-file app (`lib/main.dart`, ~3500 lines)

**Data classes:**
- `AppData` — hierarchical storage: `domain > path > url > metadata` (tags, ratings). Persisted as `data.json`.
- `RecentVideo` — playback history with position tracking. Persisted as `recent.json`.

**Main widget: `MainPage` (StatefulWidget)**
- Left pane: two stacked video players with toolbars, seek bars, and tag bars
- Right pane top: WebView browser with navigation bar
- Right pane bottom: tree view (domain > path > link hierarchy)
- Draggable separators between all panes

### Key dependencies
- **media_kit** — video playback via libmpv. The `Video` widget uses a native platform texture view.
- **webview_flutter** / **webview_flutter_wkwebview** — embedded browser using WKWebView on macOS.

### Specifications

Feature specs live in `spec/` and describe the expected behavior in detail. Always consult them before making changes:
- `0-general.md` — window layout and pane structure
- `1-browser.md` — browser, sprite preview, tagging popup
- `2-video.md` — video players, toolbar, controls, auto-rating
- `3-tree.md` — file tree, buttons (Add, Extract, Remove, Play, View)
- `4-recents.md` — recent videos page
- `5-format.md` — JSON schemas for `data.json` and `recent.json`
- `6-forum.md` — forum extraction, deduplication, preview fallback
- `9-util.md` — Python utility CLI

## Platform-specific gotchas

- **Video widget overlay**: Flutter widgets cannot render on top of media_kit's native platform view using `Stack`/`Positioned`. Use the `Video` widget's `controls` parameter to overlay interactive widgets (e.g., `GestureDetector`, `Slider`).
- **WKWebView `position:fixed`**: Does not work reliably in `loadHtmlString` content. Use `position:sticky` or static positioning instead.
- **WKWebView `loadHtmlString` with external resources**: Must pass a `baseUrl` parameter for external images/resources to load.
- **JavaScript channels**: Browser-to-Flutter communication uses `FrameClick` and `FrameRightClick` channels via `postMessage`.

## Constants

```dart
kTagKeys:   ['blo', 'dog', 'fro', 'bak', 'ass', 'cum']
kTagEmojis: ['💋', '🐕', '😀', '🍑', '🎯', '💦']
kRatingColors: [red(1=Super), amber(2=Top), green(3=Ok), blue(4=Uhm), grey(5=Bad)]
```

## Data flow

1. **Browsing**: User navigates to content sites configured in `config.json`
2. **Extraction**: Extract k2s links from current page (or forum topics) into the tree
3. **Preview**: Sprite images from `https://static-cache.k2s.cc/sprite/<id>/XX.jpeg` (5×5 grids); fallback to source page images
4. **Playback**: Resolve download URL via `util.py` API, play in media_kit player
5. **Tagging/Rating**: Tags stored per-frame, ratings per-link, both persisted in `data.json`

## Update the spec
First update the spec, then implement.
