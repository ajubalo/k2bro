# File Tree (Right Pane — Bottom)

The bottom of the right pane contains a collapsible tree view with +/- expand/collapse controls.

## Tree Structure

Reading and writing from `data.json` (see [5-format.md](5-format.md)). The tree has three top-level category nodes:

- **Fresh** — all links that have no rating and no tags
  - **Domain**
    - **Path**
      - **Link**
- **Rated** — links that have a rating but no tags
  - **Rating groups** (Super, Top, Ok, Uhm) — collapsible nodes
    - **Domain**
      - **Path**
        - **Link**
- **Tagged** — links that have at least one tag (regardless of rating)
  - **Rating groups** (Super, Top, Ok, Uhm) — collapsible nodes
    - **Domain**
      - **Path**
        - **Link**
  - Unrated tagged links appear after the rating groups, grouped by domain > path

Each top-level node shows a count of total links it contains. Rating group nodes also show a count.

**Link** shows the portion after `https://k2s.cc/file/<id>/`; if empty, shows the `<id>`. Nodes at the same level are sorted alphabetically. Empty domains/paths (with no matching links) are omitted.

Trailing slashes are always stripped from paths (e.g., `/page/3/` becomes `/page/3`).

Paths (collections) can also be rated using the rating buttons. Rated paths are sorted by rating (best first), then by trailing number within the same rating. Unrated paths appear after rated ones. The path node shows its rating color.

Paths are sorted alphabetically. Within a prefix group, children are ordered by highest trailing number first (e.g., `page20`, `page3`, `page2`). Prefix grouping itself uses ascending order so the shortest prefix is correctly detected as the group parent.

### Path Prefix Grouping

When multiple paths under a domain share a common prefix (where one path string is a prefix of others), they are grouped under a virtual ancestor node:

- The group node is named after the shortest prefix path
- The shortest prefix path itself appears as a child within the group
- The group node shows the total link count across all child paths
- The group node's background color reflects the best (lowest) rating among child paths
- Clicking a group node selects it and expands it; the Pick button scopes random selection to all links within the group's child paths
- Paths that are not prefixes of any other path remain ungrouped

Example: paths `?1`, `?1&2`, `?1&3`, `?2` produce:
```
Domain (10)
  ?1 (6)          -- group node
    ?1 (3)        -- actual path
    ?1&2 (2)      -- actual path
    ?1&3 (1)      -- actual path
  ?2 (4)          -- ungrouped path
```

For each link, tags are displayed inline. Clicking a tag jumps to that position in the video on the currently selected player.


## Button Bar

Below the tree, a button bar with: **Add**, a page-limit field, **Extract**, **Remove**, **Recents**, **Play**, **View**, **Unrate**, **Dedup**, **VR**, **Search**.

### Unrate

Removes the rating from all links under the selected node (domain, path, or single link), making them unrated (fresh).

### Add

Adds the current browser URL to the tree:
- Adds the domain if not already present, save also the protocol (http) if it nos https:
- Adds the path (unless it is the home page) including the query string

**Right-click**: Shows a dialog with a text input pre-filled with the current URL's path, allowing the user to edit the path before adding it.

### Remove

- On a **link**: removes it immediately.
- On a **path** or **domain**: asks for confirmation before removal.

**Right-click**: Shows a dialog asking for a substring. Searches all link names under the selected node (link, path, group, or domain) for matches (case-insensitive). Shows a confirmation: "Found N links with "substring" out of M links. Remove them?" before deleting.

### Extract

1. Scans the current browser page text for all links matching `https://k2s.cc/file/...`.
2. For each found link, calls the `getFilesInfo` API (see [9-util.py](9-util.py)) to check availability.
3. If `is_available` is true, adds the link to the tree.
4. If a link already exists in the tree but is no longer available, removes it (allows re-extraction to update status).
5. Does not change the hidden state of existing links.
6. After extraction, auto-navigate to the next page (checked in order, first match wins):
   - If the URL contains `start=XXX` (where XXX is a number), navigate to the same URL with XXX incremented by 30.
   - If the URL contains `pageXXX` (where XXX is a number), navigate to the same URL with XXX incremented by 1.
   - If the URL ends with `/<number>/`, increment the number by 1.
   - If the URL ends with a number, increment it by 1.

A **max-page text field** (digits only, default `0`) sits to the left of the Extract button. It sets the maximum page number for the auto-extract loop: `0` means unlimited, any other value stops when the next page number would exceed it.

**Right-click**: Starts an auto-extract loop using an **offscreen browser** (the main browser remains free for browsing). The loop extracts the current page, waits for the next page to load, and repeats. While looping, the button shows `Extract #N` (actual page number from URL) with an orange background and a stop icon. Left-clicking the button stops the loop. The loop also stops automatically when:
- There is no next page.
- Page load times out.
- The next page number exceeds the max-page value.
- 3 consecutive pages yield zero links.

For paginated URLs (those with a page number pattern), links are always stored under the URL's own page path (e.g., `/page/3/`), creating the path if it doesn't exist. If the page's path already has links, extraction skips to the next page automatically. For non-paginated URLs, links are stored under the currently selected path if one is selected in the tree (and the domain matches), otherwise under the URL's path. Deep extraction stores all links under the parent page's path (the page where deep extraction was triggered), recording each link's source page in metadata.

A **Deep** checkbox sits to the left of the Extract button. When checked, extraction follows all same-site links found on the current page, fetches each via HTTP, and collects k2s links from their HTML. Each link's source page is recorded. This is useful for blog index pages that list posts containing k2s links.

### VR

Toggles the VR flag on all links under the selected node (link, path, group, or domain):
- If any link is not VR, sets all to VR.
- If all links are already VR, clears VR on all.
- When the selected node is in a VR category (Fresh VR or Tagged VR), always clears VR on all links under the node.

### Play

Enabled when the browser is on a `https://k2s.cc/file/...` URL or when a k2s link is selected in the tree. Clicking it plays the video in the currently selected player (resolves the download URL, adds to recents, and starts playback at frame 0).


### View

Open Directly the page `https://k2s.cc/file/<id>`

## Navigation

- Clicking a **domain**, **path**, or **group** expands the node, selects it, and scrolls the tree to make it visible.
- Clicking a **domain** or **path** also opens that page in the browser.
- Clicking a **link** activates the sprite preview for that file's `<id>`.

## Preview

When clicking a link in format `https://k2s.cc/file/<id>/...`, activate the sprite preview in the browser with the `<id>` (see [1-browser.md](1-browser.md)).

## RAR Part Grouping

When multiple links under the same path match a multi-part RAR pattern (`name.part01.rar`, `name.part1.rar`, etc.), they are displayed as a single grouped entry:

- **Icon**: `archive` (instead of the normal `link` icon)
- **Label**: `baseName.rar (N parts)` — the base name without the part number, followed by the count
- **File size**: sum of all parts' file sizes
- **Rating color**: best (lowest) rating across all parts
- **Tags**: collected from all parts
- **VR prefix**: shown if any part is VR-flagged
- **Click**: selects and previews the first part (part01/part1)
- **Right-click**: hides all parts in the group
- **Rating**: setting a rating on a grouped entry applies to all parts

Lone parts (only one `partN.rar` with no siblings) display as normal link nodes. Grouping is purely visual — all individual links remain stored separately in `data.json`.

## Hiding

- **Right click** on a link marks it as hidden: it is no longer shown in the tree or the recents list.

## Position Tracking

- Track the latest position reached in each video.
- Show the most advanced frame in the recents view.
- Display a percentage of the video seen on the button bar.
- When a video reaches **90% completion**, remove it from recents.
- Remove from recents after **24 hours** since last played.

## Tag Hover Preview

Hovering on a tag in the tree shows the closest sprite frame for that tag position:
- Display a clipped portion of the corresponding sprite image.
- Close the hover preview after 3 seconds in any case.
