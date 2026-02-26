# Keep Extraction

When **Extract** is clicked and the current URL path starts with `/tags/` or `/xfsearch/`:

1. Scan the page inside the `#midside` container for all `<a>` links matching `<origin>/<number>-*.html` (where `<origin>` is the current site's scheme + host).
2. Fetch each content page via HTTP GET.
3. Find the button with `data-id` and `data-hash` attributes.
4. POST to `/engine/mods/click_hide/show.php` with form data: `id=<data-id>&hash=<data-hash>&div=1`.
5. Extract all `k2s.cc/file/` or `keep2share.cc/file/` links from the response.
6. Add the extracted links to the tree under the current domain/path, with the content page as the source page.
7. Auto-navigate to the next page.

## Dedup

A **Dedup** button in the tree button bar. When clicked:

1. Walk all links in the selected subtree (domain or path).
2. Group by file ID (`https://k2s.cc/file/<id>` or `https://keep2share.cc/file/<id>`). Remove duplicates, keeping the first occurrence. Merge tags, ratings, and source pages from removed duplicates into the keeper.
3. For bare URLs (no filename after the ID) or URLs where the name looks like a hex ID (13+ hex characters), call `getFilesInfo` to fetch the real name and replace with `https://k2s.cc/file/<id>/<name>`.
4. Remove all paths with zero links remaining. Remove the domain if it becomes empty.
5. Show progress in the browser log page (link count, duplicates found, renames, empty nodes removed).

## Collapse

When collapsing a parent node in the tree, automatically collapse all its descendant subnodes.
