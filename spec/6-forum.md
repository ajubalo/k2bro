# Forum Extraction

Special handling when **Extract** is clicked on a forum site.

## Detection

If the current browser path contains `/viewforum.php`, activate forum extraction mode.

show the detailed logs

## Extraction Flow

1. Scan the current page for all links containing `/viewtopic.php`.
2. For each topic link:
   - Fetch the linked page.
   - Extract all `https://k2s.cc/file/...` links from that page.
   - Store the topic page URL as the `source_page` for each extracted link.
3. Check availability and add links to the tree as usual.

## Deduplication

When multiple URLs share the same file ID (e.g. `https://k2s.cc/file/abc123/short.mp4` and `https://k2s.cc/file/abc123/longer-name.mp4`), keep the URL with the longest filename. Tags, ratings, and source pages from removed duplicates are merged into the kept link.

Re-extraction is safe: existing tags and ratings are preserved, unavailable links are removed, and duplicates are merged.

## Preview Fallback

When opening a link whose sprite preview is not available, fetch the link's `source_page` HTML and render a custom page showing all images wider than 200px and all k2s links found in the page. The target link is highlighted in red and the page scrolls to it automatically.

If no `source_page` is stored, fall back to the link's own `https://k2s.cc/file/<id>` URL.

